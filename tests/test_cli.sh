#!/bin/sh
# bin/curfeed のテスト。一時ディレクトリの設定 / hosts / ログを使い、実際の環境には触れない。
# 管理者権限への切り替えだけは sudo を差し替えて確認する

. "$(dirname "$0")/helpers.sh"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/sudo"
EOF
chmod +x "$WORK/bin/sudo"

setup() {
  rm -rf "$WORK/etc" "$WORK/log" "$WORK/stub"
  mkdir -p "$WORK/etc" "$WORK/log" "$WORK/stub"
  printf '127.0.0.1\tlocalhost\n' > "$WORK/hosts"
  printf '%s\n' '# SNS' 'www.youtube.com' '  x.com   # 行末コメント' > "$WORK/etc/blocklist"
  printf 'ALLOW_START=2100\nALLOW_END=2200\n' > "$WORK/etc/config"
}

# 引数: 現在時刻 HHMM, curfeed の引数...。終了コードを返す
run() {
  now=$1
  shift
  CURFEED_ETC="$WORK/etc" CURFEED_HOSTS="$WORK/hosts" CURFEED_LOG_DIR="$WORK/log" \
    CURFEED_NOW="$now" STUB_DIR="$WORK/stub" PATH="$WORK/bin:$PATH" \
    sh "$ROOT/bin/curfeed" "$@" > "$WORK/stdout" 2> "$WORK/stderr"
}

# hosts を今の時刻の状態にしておく
apply_now() {
  CURFEED_ETC="$WORK/etc" CURFEED_HOSTS="$WORK/hosts" CURFEED_NOW="$1" \
    sh "$ROOT/libexec/curfeed/apply" > /dev/null 2>&1
}

out() { cat "$WORK/stdout"; }
line() { grep "^$1" "$WORK/stdout"; }
nonzero() { if [ "$1" -ne 0 ]; then echo nonzero; else echo zero; fi; }
snapshot() { cat "$WORK/etc/blocklist" "$WORK/etc/config" "$WORK/hosts"; }

echo "status"
setup; apply_now 2000; run 2000 status
check "ブロック中の状態" "$(line '状態:')" "状態: ブロック中"
check "許可時間帯を表示する" "$(line '許可時間帯:')" "許可時間帯: 21:00〜22:00"
check "次の解除までの時間を表示する" "$(line '次の解除:')" "次の解除: 21:00（あと1時間）"
check "ブロック対象の数を表示する" "$(line 'ブロック対象:')" "ブロック対象: 2 ドメイン"
check "hosts に反映済みなら注意を出さない" "$(grep -c '反映' "$WORK/stdout")" 0
setup; apply_now 2130; run 2130 status
check "許可中の状態" "$(line '状態:')" "状態: 許可中"
check "次のブロックまでの時間を表示する" "$(line '次のブロック:')" "次のブロック: 22:00（あと30分）"
setup; apply_now 2230; run 2230 status
check "日付をまたいだ残り時間" "$(line '次の解除:')" "次の解除: 21:00（あと22時間30分）"
setup; apply_now 2059; run 2059 status
check "残り1分" "$(line '次の解除:')" "次の解除: 21:00（あと1分）"
setup; run 2000 status
check "hosts が時刻の状態と違えば注意を出す" "$(grep -c 'hosts にはまだ反映されていません' "$WORK/stdout")" 1
setup; apply_now 2000; run 2000
check "引数なしは status と同じ" "$(line '状態:')" "状態: ブロック中"
setup; rm "$WORK/etc/config"; run 2000 status; status=$?
check "設定ファイルが無ければエラー終了する" "$(nonzero $status)" nonzero
setup; printf '# コメントだけ\n' > "$WORK/etc/blocklist"; run 2000 status
check "ブロック対象が空なら 0 ドメインと表示する" "$(line 'ブロック対象:')" "ブロック対象: 0 ドメイン"
check "ブロック対象が空なら登録方法を案内する" "$(grep -c 'curfeed add' "$WORK/stdout")" 1
check "ブロック対象が空なら hosts の反映待ちの注意は出さない" "$(grep -c '反映' "$WORK/stdout")" 0

setup_multi() { setup; printf 'ALLOW=1200-1300,2100-2200\n' > "$WORK/etc/config"; }
setup_multi; apply_now 1000; run 1000 status
check "複数の許可時間帯を並べて表示する" "$(line '許可時間帯:')" "許可時間帯: 12:00〜13:00, 21:00〜22:00"
check "次に始まる許可時間帯までの時間を表示する" "$(line '次の解除:')" "次の解除: 12:00（あと2時間）"
setup_multi; apply_now 1230; run 1230 status
check "昼の許可時間帯の中なら許可中" "$(line '状態:')" "状態: 許可中"
check "今いる許可時間帯の終わりを表示する" "$(line '次のブロック:')" "次のブロック: 13:00（あと30分）"
setup_multi; apply_now 1400; run 1400 status
check "昼が終わったら次は夜の許可時間帯" "$(line '次の解除:')" "次の解除: 21:00（あと7時間）"
setup_multi; apply_now 2230; run 2230 status
check "夜が終わったら次は翌日の昼の許可時間帯" "$(line '次の解除:')" "次の解除: 12:00（あと13時間30分）"
setup; printf 'ALLOW=2300-0100\n' > "$WORK/etc/config"; apply_now 0030; run 0030 status
check "日付をまたぐ許可時間帯の中なら、その終わりを表示する" "$(line '次のブロック:')" "次のブロック: 01:00（あと30分）"

setup; printf 'ALLOW_START=0000\nALLOW_END=2400\n' > "$WORK/etc/config"; apply_now 2030; run 2030 status
check "24 時間許可なら許可中" "$(line '状態:')" "状態: 許可中"
check "24 時間許可であることを表示する" "$(line '許可時間帯:')" "許可時間帯: 00:00〜24:00（24時間）"
check "24 時間許可なら次のブロックは無い" "$(line '次のブロック:')" "次のブロック: なし"
check "24 時間許可なら set-time で決めるよう案内する" "$(grep -c 'curfeed set-time' "$WORK/stdout")" 1
check "24 時間許可なら hosts の反映待ちの注意は出さない" "$(grep -c '反映' "$WORK/stdout")" 0
setup; apply_now 2000; run 2000 status
check "24 時間でなければ set-time の案内は出さない" "$(grep -c 'curfeed set-time' "$WORK/stdout")" 0

echo "list"
setup; run 2000 list
check "ドメインだけを1行ずつ表示する" "$(out)" "www.youtube.com
x.com"
setup; printf '# コメントだけ\n' > "$WORK/etc/blocklist"; run 2000 list; status=$?
check "空なら登録されていないことと登録方法を伝える" "$(out)" "ブロックするドメインは登録されていません（curfeed add youtube.com のように登録できます）"
check "空でも終了コード 0" "$status" 0

echo "add"
setup; run 2130 add tiktok.com; status=$?
check "追加は終了コード 0" "$status" 0
run 2130 list
check "追加したドメインが一覧に出る" "$(out)" "www.youtube.com
x.com
tiktok.com"
setup; run 2130 add 'https://www.TikTok.com/@user?x=1'
check_has_line "URL を渡すとホスト名（小文字）を追加する" "$WORK/etc/blocklist" "www.tiktok.com"
setup; run 2130 add x.com; status=$?
check "登録済みのドメインは追加しない" "$(grep -c 'x.com' "$WORK/etc/blocklist")" 1
check "登録済みでも終了コード 0" "$status" 0
check "登録済みであることを伝える" "$(grep -c '登録済みです: x.com' "$WORK/stdout")" 1
setup; before=$(snapshot); run 2130 add 'not a domain!'; status=$?
check "不正なドメインはエラー終了する" "$(nonzero $status)" nonzero
check "不正なドメインのときは何も変えない" "$(snapshot)" "$before"
setup; before=$(snapshot); run 2130 add tiktok.com 'bad_domain'
check "1つでも不正なら1つも追加しない" "$(snapshot)" "$before"
setup; run 2130 add; status=$?
check "ドメインを指定しなければエラー終了する" "$(nonzero $status)" nonzero
setup; apply_now 2000; run 2000 add tiktok.com
check_has_line "ブロック中に追加すると hosts にすぐ反映する" "$WORK/hosts" "0.0.0.0 tiktok.com"
check "反映した記録をログに残す" "$(grep -c 'ブロックしました' "$WORK/log/curfeed.log")" 1
setup; chmod 444 "$WORK/etc/blocklist"; before=$(snapshot); run 2130 add tiktok.com
check "書き込めなければ sudo で実行し直す" "$(sed 's/^.*bin\/curfeed //' "$WORK/stub/sudo" 2>/dev/null)" "add tiktok.com"
check "sudo で実行し直す前に何も変えない" "$(snapshot)" "$before"

echo "remove"
setup; run 2130 remove x.com; status=$?
check "削除は終了コード 0" "$status" 0
run 2130 list
check "削除したドメインは一覧から消える" "$(out)" "www.youtube.com"
check_has_line "削除してもコメント行は残す" "$WORK/etc/blocklist" "# SNS"
setup; apply_now 2000; run 2000 remove x.com
check_no_line "ブロック中に削除すると hosts からすぐ消える" "$WORK/hosts" "0.0.0.0 x.com"
check_has_line "削除していないドメインはブロックしたまま" "$WORK/hosts" "0.0.0.0 www.youtube.com"
setup; run 2130 remove 'https://x.com/home'
check_no_line "URL を渡すとホスト名で削除する" "$WORK/etc/blocklist" "  x.com   # 行末コメント"
setup; before=$(snapshot); run 2130 remove x.com example.com; status=$?
check "登録されていないドメインはエラー終了する" "$(nonzero $status)" nonzero
check "1つでも登録されていなければ1つも削除しない" "$(snapshot)" "$before"
setup; run 2130 remove; status=$?
check "ドメインを指定しなければエラー終了する" "$(nonzero $status)" nonzero

echo "set-time"
allow() { grep '^ALLOW' "$WORK/etc/config" | tr '\n' ' '; }
setup; run 2130 set-time 20:00 23:00; status=$?
check "今の書き方（開始 終了）も使える" "$status" 0
check "設定ファイルには ALLOW= の形で書く" "$(allow)" "ALLOW=2000-2300 "
run 2130 status
check "変更後の許可時間帯を表示する" "$(line '許可時間帯:')" "許可時間帯: 20:00〜23:00"
setup; run 2130 set-time 0700 0800
check "HHMM でも設定できる" "$(allow)" "ALLOW=0700-0800 "
setup; run 2130 set-time 12:00-13:00 21:00-22:00; status=$?
check "範囲を並べて複数の許可時間帯を設定できる" "$(allow)" "ALLOW=1200-1300,2100-2200 "
check "複数でも終了コード 0" "$status" 0
check "変更後の許可時間帯をまとめて伝える" "$(grep -c '12:00〜13:00, 21:00〜22:00 に変更しました' "$WORK/stdout")" 1
setup; run 2130 set-time 1200-1300
check "範囲は HHMM-HHMM でも書ける" "$(allow)" "ALLOW=1200-1300 "
setup; run 2130 set-time 21:00-22:00 12:00-14:00 13:00-15:00
check "重なる時間帯はまとめ、時刻順に並べて保存する" "$(allow)" "ALLOW=1200-1500,2100-2200 "
setup; run 2130 set-time 12:00-13:00; run 2130 set-time 21:00-22:00
check "set-time は前の許可時間帯を置き換える（追加ではない）" "$(allow)" "ALLOW=2100-2200 "
setup; apply_now 2030; run 2030 set-time 20:00 23:00
check_no_line "許可時間帯に入る変更をすると hosts のブロックをすぐ外す" "$WORK/hosts" "0.0.0.0 www.youtube.com"
setup; apply_now 1230; run 1230 set-time 12:00-13:00 21:00-22:00
check_no_line "複数のうちどれかに入る変更をすると hosts のブロックをすぐ外す" "$WORK/hosts" "0.0.0.0 www.youtube.com"
setup; apply_now 2030; run 2030 set-time 00:00 24:00
check "00:00 24:00 で 24 時間許可（制限なし）に戻せる" "$(allow)" "ALLOW=0000-2400 "
check_no_line "24 時間許可に戻すと hosts のブロックをすぐ外す" "$WORK/hosts" "0.0.0.0 www.youtube.com"
setup; run 2030 set-time 00:00-24:00
check "00:00-24:00 でも 24 時間許可に戻せる" "$(allow)" "ALLOW=0000-2400 "
for args in "25:00 23:00" "21:00 2100" "12:00-12:00" "24:00-01:00" "12:00-13:00 25:00-26:00" \
  "12:00-13:00 21:00" "21:00 22:00 23:00" "12:00~13:00" "21:00"; do
  setup; before=$(snapshot); run 2130 set-time $args; status=$?
  if [ "$status" -ne 0 ] && [ "$(snapshot)" = "$before" ] && [ -s "$WORK/stderr" ]; then
    ok "不正な指定（$args）はエラー終了し、何も変えない"
  else
    ng "不正な指定（$args）はエラー終了し、何も変えない" "status=$status $(allow)"
  fi
done
setup; run 2130 set-time; status=$?
check "引数が無ければエラー終了する" "$(nonzero $status)" nonzero

echo "log"
setup
printf '%s\n' '2026-10-23 17:57 ブロックしました' '2026-10-23 22:00 ブロックしました' > "$WORK/log/curfeed.log"
printf '%s\n' '2026-10-23 18:16 タブを 8 件閉じました' '2026-10-23 22:00 タブを 2 件閉じました' > "$WORK/log/curfeed-close-tabs.log"
run 2130 log
check "2つのログを時刻順にまとめる（同じ時刻は切り替えが先）" "$(out)" "2026-10-23 17:57 ブロックしました
2026-10-23 18:16 タブを 8 件閉じました
2026-10-23 22:00 ブロックしました
2026-10-23 22:00 タブを 2 件閉じました"
run 2130 log 1
check "件数を指定できる" "$(out)" "2026-10-23 22:00 タブを 2 件閉じました"
run 2130 log abc; status=$?
check "件数が数字でなければエラー終了する" "$(nonzero $status)" nonzero
setup; run 2130 log
check "ログが無ければその旨を表示する" "$(out)" "記録はありません"

echo "uninstall"
# インストール後と同じ配置（bin/ と libexec/curfeed/ に uninstall.sh がある）を一時ディレクトリに作る。
# uninstall.sh は呼ばれたことだけを記録する差し替え版にする
setup_installed() {
  setup
  rm -rf "$WORK/prefix"
  mkdir -p "$WORK/prefix"
  cp -R "$ROOT/bin" "$ROOT/libexec" "$WORK/prefix/"
  printf '#!/bin/sh\necho ran >> "$STUB_DIR/uninstall"\n' > "$WORK/prefix/libexec/curfeed/uninstall.sh"
}
# 引数: curfeed の引数...。標準入力は呼び出し側から渡す
run_installed() {
  CURFEED_ETC="$WORK/etc" CURFEED_HOSTS="$WORK/hosts" CURFEED_LOG_DIR="$WORK/log" \
    STUB_DIR="$WORK/stub" PATH="$WORK/bin:$PATH" \
    sh "$WORK/prefix/bin/curfeed" "$@" > "$WORK/stdout" 2> "$WORK/stderr"
}
sudo_args() { sed 's/^.*bin\/curfeed //' "$WORK/stub/sudo" 2>/dev/null; }
uninstall_runs() { if [ -e "$WORK/stub/uninstall" ]; then wc -l < "$WORK/stub/uninstall" | tr -d ' '; else echo 0; fi; }

setup_installed; printf 'n\n' | run_installed uninstall; status=$?
check "確認で n なら終了コードは 0 以外" "$(nonzero $status)" nonzero
check "確認で n なら中止したことを伝える" "$(grep -c '中止しました' "$WORK/stdout")" 1
check "確認で n なら sudo も uninstall.sh も呼ばない" "$(sudo_args)$(uninstall_runs)" "0"
setup_installed; printf '\n' | run_installed uninstall
check "Enter だけなら（既定の No で）中止する" "$(sudo_args)$(uninstall_runs)" "0"
setup_installed; printf 'y\n' | run_installed uninstall; status=$?
check "確認で y なら確認を省いて sudo で実行し直す" "$(sudo_args)" "uninstall --yes"
setup_installed; run_installed uninstall --yes < /dev/null
check "--yes なら確認せずに sudo で実行し直す" "$(sudo_args)" "uninstall --yes"
setup_installed; mkdir -p "$WORK/rootbin"
printf '#!/bin/sh\necho 0\n' > "$WORK/rootbin/id"; chmod +x "$WORK/rootbin/id"
CURFEED_ETC="$WORK/etc" STUB_DIR="$WORK/stub" PATH="$WORK/rootbin:$WORK/bin:$PATH" \
  sh "$WORK/prefix/bin/curfeed" uninstall --yes < /dev/null > "$WORK/stdout" 2> "$WORK/stderr"
check "root なら uninstall.sh を実行する" "$(uninstall_runs)" 1
check "root なら sudo は使わない" "$(sudo_args)" ""
setup; run 2130 uninstall --yes < /dev/null; status=$?
check "インストールされていない（リポジトリから実行した）ならエラー終了する" "$(nonzero $status)" nonzero
check "リポジトリの uninstall.sh を案内する" "$(grep -c 'sudo ./uninstall.sh' "$WORK/stderr")" 1
setup_installed; run_installed uninstall --force < /dev/null; status=$?
check "不明なオプションはエラー終了する" "$(nonzero $status)" nonzero
check "不明なオプションのときは sudo も uninstall.sh も呼ばない" "$(sudo_args)$(uninstall_runs)" "0"

echo "その他"
setup; run 2130 help; status=$?
check "help は終了コード 0" "$status" 0
check "help で使い方を表示する" "$(grep -c '^使い方: curfeed' "$WORK/stdout")" 1
check "help に uninstall を載せる" "$(grep -c '^  uninstall' "$WORK/stdout")" 1
setup; run 2130 unknown-command; status=$?
check "不明なコマンドは終了コード 2" "$status" 2
check "不明なコマンドを伝える" "$(grep -c '不明なコマンドです: unknown-command' "$WORK/stderr")" 1

finish
