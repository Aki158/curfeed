#!/bin/sh
# install.sh のテスト。/usr/local・/Library・/etc/hosts などの置き場所をすべて一時ディレクトリに差し替え、
# root かどうかの判定（id）、持ち主を root にする操作（install -o / chown）、ログイン中のユーザーの判定（stat）、
# launchd への操作（launchctl）、待ち時間（sleep）だけを差し替えて実行する

. "$(dirname "$0")/helpers.sh"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/id" <<'EOF'
#!/bin/sh
echo "$STUB_UID"
EOF
# ログイン中のユーザーの ID（stat -f %u /dev/console）
cat > "$WORK/bin/stat" <<'EOF'
#!/bin/sh
echo "$STUB_CONSOLE_UID"
EOF
# 持ち主（-o / -g）は記録だけして、コピーと権限（-m）の設定は実際に行う
cat > "$WORK/bin/install" <<'EOF'
#!/bin/sh
while getopts m:o:g: opt; do
  case $opt in
    m) mode=$OPTARG ;;
    o) owner=$OPTARG ;;
    g) group=$OPTARG ;;
  esac
done
shift $((OPTIND - 1))
cp "$1" "$2" && chmod "$mode" "$2" && echo "$owner:$group $2" >> "$STUB_DIR/install"
EOF
cat > "$WORK/bin/chown" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/chown"
EOF
# 登録されているジョブを「ドメイン_ラベル」のファイルで覚え、print はそれで答える
cat > "$WORK/bin/launchctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/launchctl"
key() { printf '%s' "$1" | tr '/' '_'; }
case $1 in
  bootstrap) touch "$STUB_DIR/loaded-$(key "$2/$(basename "$3" .plist)")" ;;
  bootout) rm -f "$STUB_DIR/loaded-$(key "$2/$(basename "$3" .plist)")" ;;
  print) [ -e "$STUB_DIR/loaded-$(key "$2")" ] ;;
esac
EOF
printf '#!/bin/sh\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/"*

SYS="$WORK/sys"
PREFIX="$SYS/usr/local"
LIBRARY="$SYS/Library"
ORIGINAL_HOSTS="$(printf '127.0.0.1\tlocalhost\n# 手書きの行')"

# まだ何もインストールされていない Mac を作る
setup() {
  rm -rf "$SYS" "$WORK/stub"
  mkdir -p "$WORK/stub" "$SYS/usr/local" "$LIBRARY/LaunchDaemons" "$LIBRARY/LaunchAgents" "$SYS/log"
  printf '%s\n' "$ORIGINAL_HOSTS" > "$SYS/hosts"
  stub_uid=0
  stub_console_uid=501
}

run() {
  CURFEED_PREFIX="$PREFIX" CURFEED_LIBRARY="$LIBRARY" CURFEED_ETC="$SYS/etc/curfeed" \
    CURFEED_HOSTS="$SYS/hosts" CURFEED_LOG_DIR="$SYS/log" CURFEED_NOW=1200 \
    STUB_UID="$stub_uid" STUB_CONSOLE_UID="$stub_console_uid" STUB_DIR="$WORK/stub" PATH="$WORK/bin:$PATH" \
    sh "$ROOT/install.sh" > "$WORK/stdout" 2> "$WORK/stderr"
}

# 引数: テスト名 リポジトリのファイル インストール先 権限（8進数）
check_installed() {
  if ! cmp -s "$ROOT/$2" "$3"; then
    ng "$1" "$3 がリポジトリの $2 と違います（または無い）"
  elif [ "$(/usr/bin/stat -f %Lp "$3")" != "$4" ]; then
    ng "$1" "権限が $(/usr/bin/stat -f %Lp "$3") です（期待: ${4}）"
  else
    ok "$1"
  fi
}

count() { grep -c -- "$1" "$WORK/stdout"; }

DAEMON_PLIST="$LIBRARY/LaunchDaemons/local.curfeed.plist"
AGENT_PLIST="$LIBRARY/LaunchAgents/local.curfeed.close-tabs.plist"

echo "初めてのインストール"
setup; run; status=$?
check "終了コード 0" "$status" 0
check_installed "コマンドを置く" bin/curfeed "$PREFIX/bin/curfeed" 755
check_installed "共通の関数を置く（実行はしないので 644）" libexec/curfeed/lib.sh "$PREFIX/libexec/curfeed/lib.sh" 644
check_installed "hosts を書き換える処理を置く" libexec/curfeed/apply "$PREFIX/libexec/curfeed/apply" 755
check_installed "タブを閉じる処理を置く" libexec/curfeed/close-tabs "$PREFIX/libexec/curfeed/close-tabs" 755
check_installed "アンインストールの処理を置く" uninstall.sh "$PREFIX/libexec/curfeed/uninstall.sh" 755
check_installed "hosts を書き換えるジョブの設定を置く" launchd/local.curfeed.plist "$DAEMON_PLIST" 644
check_installed "タブを閉じるジョブの設定を置く" launchd/local.curfeed.close-tabs.plist "$AGENT_PLIST" 644
check "置いたファイルはすべて持ち主を root にする（root 以外が書き換えられないように）" \
  "$(grep -vc '^root:wheel ' "$WORK/stub/install")" 0
check "元の hosts を退避する" "$(cat "$SYS/hosts.before-curfeed")" "$ORIGINAL_HOSTS"
check "hosts は変えない（書き換えるのはジョブ）" "$(cat "$SYS/hosts")" "$ORIGINAL_HOSTS"
check_has_line "許可時間帯は 24 時間で始める" "$SYS/etc/curfeed/config" "ALLOW=0000-2400"
check "ブロックするドメインは空で始める" "$(grep -cv '^#' "$SYS/etc/curfeed/blocklist")" 0
check "タブを閉じるジョブのログは、ログイン中のユーザーが書けるようにする" \
  "$(cat "$WORK/stub/chown")" "501 $SYS/log/curfeed-close-tabs.log"
check "hosts を書き換えるジョブを登録する" "$(grep -c "^bootstrap system $DAEMON_PLIST\$" "$WORK/stub/launchctl")" 1
check "タブを閉じるジョブを、ログイン中のユーザーの画面セッションに登録する" \
  "$(grep -c "^bootstrap gui/501 $AGENT_PLIST\$" "$WORK/stub/launchctl")" 1
check "登録されていないジョブは止めない" "$(grep -c '^bootout' "$WORK/stub/launchctl")" 0
check "「インストールしました」と表示する" "$(head -n 2 "$WORK/stdout" | grep -cx 'インストールしました')" 1
check "Chrome の操作許可の確認が出ることを伝える" "$(count 'Google Chrome を制御しようとしています')" 1
check "README の QUIC を止める手順を案内する" "$(count 'README の「Chrome の QUIC（HTTP/3）を止める」')" 1
check "詳しい使い方は curfeed help に任せる" "$(grep -cx '使い方: curfeed help' "$WORK/stdout")" 1
check "最後に今の状態を表示する" "$(count '^状態: 許可中')" 1
check "次にやること（add / set-time）の案内は status の1回だけ" "$(count 'curfeed add')" 1

echo "入れ直し（設定を引き継ぐ）"
setup; run
printf 'ALLOW=2100-2200\n' > "$SYS/etc/curfeed/config"
printf 'x.com\n' > "$SYS/etc/curfeed/blocklist"
printf '# 古い版\n' > "$PREFIX/libexec/curfeed/apply"
printf '127.0.0.1\tlocalhost\n# >>> curfeed >>>\n0.0.0.0 x.com\n:: x.com\n# <<< curfeed <<<\n' > "$SYS/hosts"
rm "$WORK/stub/launchctl"
run; status=$?
check "終了コード 0" "$status" 0
check_installed "古い本体を新しいものに置き換える" libexec/curfeed/apply "$PREFIX/libexec/curfeed/apply" 755
check "設定を上書きしない" "$(cat "$SYS/etc/curfeed/config")" "ALLOW=2100-2200"
check "ブロックするドメインを上書きしない" "$(cat "$SYS/etc/curfeed/blocklist")" "x.com"
check "退避した元の hosts を上書きしない" "$(cat "$SYS/hosts.before-curfeed")" "$ORIGINAL_HOSTS"
check "登録済みのジョブは、止めてから登録し直す" "$(grep -E '^(bootout|bootstrap)' "$WORK/stub/launchctl")" \
  "$(printf 'bootout system %s\nbootstrap system %s\nbootout gui/501 %s\nbootstrap gui/501 %s' \
    "$DAEMON_PLIST" "$DAEMON_PLIST" "$AGENT_PLIST" "$AGENT_PLIST")"
check "設定を引き継いだことを表示する" "$(head -n 2 "$WORK/stdout" | grep -cx 'インストールしました（設定は引き継いでいます）')" 1
check "Chrome の操作許可の説明は出さない" "$(count 'Google Chrome を制御しようとしています')" 0
check "QUIC の案内は出さない" "$(count 'QUIC')" 0
check "詳しい使い方は curfeed help に任せる" "$(grep -cx '使い方: curfeed help' "$WORK/stdout")" 1
check "最後に今の状態を表示する" "$(count '^状態: ブロック中')" 1

echo "ログイン中のユーザーがいないとき（ログイン画面や ssh から実行）"
setup; stub_console_uid=0; run; status=$?
check "終了コード 0" "$status" 0
check "hosts を書き換えるジョブは登録する" "$(grep -c "^bootstrap system " "$WORK/stub/launchctl")" 1
check "タブを閉じるジョブは登録しない（次にログインしたときに launchd が登録する）" \
  "$(grep -c 'gui/' "$WORK/stub/launchctl")" 0

echo "異常系"
setup; stub_uid=501; run; status=$?
check "root でなければ終了コードが 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero
check "root でなければ sudo で実行するよう伝える" "$(grep -c 'sudo ./install.sh' "$WORK/stderr")" 1
check "root でなければ何も置かない" "$(find "$SYS" -type f | grep -v "/hosts\$" | wc -l | tr -d ' ')" 0

finish
