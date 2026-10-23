#!/bin/sh
# libexec/curfew/close-tabs のテスト。Chrome の操作（pgrep / pkill / osascript）だけを差し替え、
# 一時ディレクトリの hosts / 状態の記録を使う。実際の Chrome や /etc/hosts には触れない

. "$(dirname "$0")/helpers.sh"

# 差し替え用の pgrep / pkill / osascript。呼ばれ方を $STUB_DIR に記録する
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pgrep" <<'EOF'
#!/bin/sh
[ -e "$STUB_DIR/chrome-running" ]
EOF
cat > "$WORK/bin/pkill" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/pkill"
echo pkill >> "$STUB_DIR/order"
EOF
cat > "$WORK/bin/osascript" <<'EOF'
#!/bin/sh
echo call >> "$STUB_DIR/calls"
case $2 in
  *"close (tab id"*)
    shift 2
    echo "$*" >> "$STUB_DIR/closed"
    echo close >> "$STUB_DIR/order"
    ;;
  *)
    if [ -e "$STUB_DIR/list-error" ]; then
      echo "execution error: Not authorized to send Apple events to Google Chrome. (-1743)" >&2
      exit 1
    fi
    cat "$STUB_DIR/tabs"
    ;;
esac
EOF
chmod +x "$WORK/bin/pgrep" "$WORK/bin/pkill" "$WORK/bin/osascript"

BLOCK_SECTION='# >>> curfew >>>
0.0.0.0 www.youtube.com
:: www.youtube.com
0.0.0.0 youtube.com
:: youtube.com
0.0.0.0 x.com
:: x.com
# <<< curfew <<<
'

# 引数: blocked|allowed。前回の状態は「ブロック中」から始める（ブロックが続いている状態）
setup() {
  rm -rf "$WORK/stub" "$WORK/data"
  mkdir -p "$WORK/stub" "$WORK/data"
  echo blocked > "$WORK/data/state"
  if [ "$1" = blocked ]; then
    printf '127.0.0.1\tlocalhost\n%s' "$BLOCK_SECTION" > "$WORK/hosts"
  else
    printf '127.0.0.1\tlocalhost\n' > "$WORK/hosts"
  fi
  touch "$WORK/stub/chrome-running"
  : > "$WORK/stub/tabs"
}

# 引数: ウィンドウID タブID URL
add_tab() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$WORK/stub/tabs"; }

run() {
  CURFEW_HOSTS="$WORK/hosts" CURFEW_DATA="$WORK/data" \
    STUB_DIR="$WORK/stub" PATH="$WORK/bin:$PATH" \
    sh "$ROOT/libexec/curfew/close-tabs" > "$WORK/stdout" 2> "$WORK/stderr"
}

closed() { cat "$WORK/stub/closed" 2>/dev/null; }
resets() { if [ -e "$WORK/stub/pkill" ]; then wc -l < "$WORK/stub/pkill" | tr -d ' '; else echo 0; fi; }
calls() { if [ -e "$WORK/stub/calls" ]; then wc -l < "$WORK/stub/calls" | tr -d ' '; else echo 0; fi; }

echo "Chrome を操作しない場合"
setup allowed; add_tab 1 11 'https://www.youtube.com/watch?v=abc'; run; status=$?
check "許可時間（ブロック区間なし）は Chrome に問い合わせない" "$(calls)" 0
check "許可時間は終了コード 0" "$status" 0

setup blocked; rm "$WORK/stub/chrome-running"; add_tab 1 11 'https://www.youtube.com/'; run
check "Chrome が起動していなければ osascript を呼ばない（Chrome を起動させない）" "$(calls)" 0

setup blocked; add_tab 1 11 'https://www.google.com/'; run
check "ブロック対象のタブが無ければ閉じる命令を出さない" "$(closed)" ""
check "ブロック対象のタブが無ければ何も出力しない" "$(cat "$WORK/stdout")" ""

echo "閉じるタブの判定"
setup blocked
add_tab 1 11 'https://www.youtube.com/watch?v=abc'
add_tab 1 12 'https://www.google.com/search?q=youtube.com'
add_tab 1 13 'https://x.com/home'
add_tab 2 21 'https://music.youtube.com/'
add_tab 2 22 'https://www.youtube.com.example.net/'
add_tab 2 23 'https://youtube.com:443/shorts/xyz'
add_tab 2 24 'http://WWW.YOUTUBE.COM/'
add_tab 2 25 'chrome://settings/'
add_tab 3 31 'https://notyoutube.com/'
add_tab 3 32 'https://x.com'
add_tab 3 33 'https://user@x.com/path'
run
check "hosts でブロック中のホストのタブだけを（全ウィンドウから）閉じる" "$(closed)" "1 11 1 13 2 23 2 24 3 32 3 33"
check "閉じた件数をログに出す" "$(grep -c 'タブを 6 件閉じました' "$WORK/stdout")" 1

echo "接続のリセット（Chrome の通信プロセスの再起動）"
setup blocked; echo allowed > "$WORK/data/state"; run
check "ブロックが始まったら、閉じるタブが無くても接続をリセットする" "$(resets)" 1
check "リセットしたことをログに出す" "$(grep -c '接続をリセットしました' "$WORK/stdout")" 1
check "ブロック中であることを記録する" "$(cat "$WORK/data/state")" blocked
check "リセットするのは自分の Chrome の通信プロセスだけ" "$(cat "$WORK/stub/pkill")" \
  "-U $(id -u) -f Google Chrome\.app/.*--utility-sub-type=network\.mojom\.NetworkService"
setup blocked; rm "$WORK/data/state"; run
check "状態の記録が無い（インストール直後の）ブロック中もリセットする" "$(resets)" 1
setup blocked; add_tab 1 11 'https://www.google.com/'; run
check "ブロックが続いていて閉じるタブも無ければリセットしない" "$(resets)" 0
setup blocked; add_tab 1 11 'https://www.youtube.com/watch?v=abc'; run
check "ブロック中に対象のタブを見つけたら、閉じてからリセットする" "$(tr '\n' ' ' < "$WORK/stub/order")" "close pkill "
setup allowed; run
check "許可時間はリセットしない" "$(resets)" 0
check "許可時間であることを記録する" "$(cat "$WORK/data/state")" allowed
setup blocked; echo allowed > "$WORK/data/state"; rm "$WORK/stub/chrome-running"; run
check "Chrome が起動していなければリセットしない" "$(resets)" 0
setup blocked; echo allowed > "$WORK/data/state"; touch "$WORK/stub/list-error"; run; status=$?
check "タブ一覧を取得できなくても、ブロック開始時のリセットはする" "$(resets)" 1
check "タブ一覧を取得できなければ、リセットしても終了コードは 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero

echo "異常系"
setup blocked; touch "$WORK/stub/list-error"; add_tab 1 11 'https://www.youtube.com/'; run; status=$?
check "タブ一覧の取得に失敗したら終了コードが 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero
check "タブ一覧の取得に失敗したら閉じる命令を出さない" "$(closed)" ""
check "失敗理由（osascript のエラー）を stderr に出す" "$(grep -c '\-1743' "$WORK/stderr")" 1

setup blocked; rm "$WORK/hosts"; run; status=$?
check "hosts を読めなければ終了コードが 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero
check "hosts を読めなければ Chrome に問い合わせない" "$(calls)" 0
if grep -q '^20[0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9] curfew close-tabs:' "$WORK/stderr"; then
  ok "エラー行は日時から始まる"
else
  ng "エラー行は日時から始まる" "$(cat "$WORK/stderr")"
fi

finish
