#!/bin/sh
# uninstall.sh のテスト。/usr/local・/Library・/etc/hosts などの置き場所をすべて一時ディレクトリに差し替え、
# root かどうかの判定（id）と OS への操作（launchctl / dscacheutil / killall）だけを差し替えて実行する

. "$(dirname "$0")/helpers.sh"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/id" <<'EOF'
#!/bin/sh
echo "${STUB_UID:-0}"
EOF
cat > "$WORK/bin/launchctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/launchctl"
EOF
printf '#!/bin/sh\n' > "$WORK/bin/dscacheutil"
printf '#!/bin/sh\n' > "$WORK/bin/killall"
chmod +x "$WORK/bin/id" "$WORK/bin/launchctl" "$WORK/bin/dscacheutil" "$WORK/bin/killall"

SYS="$WORK/sys"
PREFIX="$SYS/usr/local"
DATA="$SYS/data dir/curfeed"

# インストール済みの状態を作る。curfeed と関係ないファイルも置き、消されないことを確かめる
setup() {
  rm -rf "$SYS" "$WORK/stub"
  mkdir -p "$WORK/stub" "$PREFIX/bin" "$PREFIX/libexec/curfeed" "$SYS/Library/LaunchDaemons" \
    "$SYS/Library/LaunchAgents" "$SYS/etc/curfeed" "$SYS/etc/other" "$SYS/log" "$DATA"
  touch "$PREFIX/bin/curfeed" "$PREFIX/libexec/curfeed/lib.sh" "$PREFIX/libexec/curfeed/apply" \
    "$SYS/Library/LaunchDaemons/local.curfeed.plist" "$SYS/Library/LaunchAgents/local.curfeed.close-tabs.plist"
  printf 'ALLOW=2100-2200\n' > "$SYS/etc/curfeed/config"
  printf 'x.com\n' > "$SYS/etc/curfeed/blocklist"
  printf '127.0.0.1\tlocalhost\n# 手書きの行\n# >>> curfeed >>>\n0.0.0.0 x.com\n:: x.com\n# <<< curfeed <<<\n' > "$SYS/hosts"
  printf '127.0.0.1\tlocalhost\n' > "$SYS/hosts.before-curfeed"
  echo log > "$SYS/log/curfeed.log"
  echo log > "$SYS/log/curfeed-close-tabs.log"
  echo blocked > "$DATA/state"
  touch "$PREFIX/bin/other-tool" "$SYS/log/system.log"
}

run() {
  CURFEED_PREFIX="$PREFIX" CURFEED_LIBRARY="$SYS/Library" CURFEED_ETC="$SYS/etc/curfeed" \
    CURFEED_HOSTS="$SYS/hosts" CURFEED_LOG_DIR="$SYS/log" CURFEED_DATA="$DATA" \
    STUB_DIR="$WORK/stub" PATH="$WORK/bin:$PATH" \
    sh "$ROOT/uninstall.sh" "$@" > "$WORK/stdout" 2> "$WORK/stderr"
}

# 引数: テスト名 パス...。すべて無ければ ok
check_gone() {
  name=$1
  shift
  left=""
  for p in "$@"; do
    if [ -e "$p" ]; then left="$left $p"; fi
  done
  if [ -z "$left" ]; then ok "$name"; else ng "$name" "残っている:$left"; fi
}
# 引数: テスト名 パス...。すべて有れば ok
check_kept() {
  name=$1
  shift
  missing=""
  for p in "$@"; do
    if [ ! -e "$p" ]; then missing="$missing $p"; fi
  done
  if [ -z "$missing" ]; then ok "$name"; else ng "$name" "消えている:$missing"; fi
}

PROGRAM="$PREFIX/bin/curfeed $PREFIX/libexec/curfeed $SYS/Library/LaunchDaemons/local.curfeed.plist $SYS/Library/LaunchAgents/local.curfeed.close-tabs.plist"
UNRELATED="$PREFIX/bin/other-tool $SYS/etc/other $SYS/log/system.log"
EXPECTED_HOSTS="$(printf '127.0.0.1\tlocalhost\n# 手書きの行')"

echo "通常のアンインストール"
setup; run; status=$?
check "終了コード 0" "$status" 0
check_gone "本体と launchd の設定を削除する" $PROGRAM
check "2つのジョブを止める" "$(grep -c '^bootout' "$WORK/stub/launchctl")" 2
check "hosts からブロック区間だけを取り除く" "$(cat "$SYS/hosts")" "$EXPECTED_HOSTS"
check_kept "設定・ログ・元の hosts・状態の記録は残す" "$SYS/etc/curfeed/config" "$SYS/etc/curfeed/blocklist" \
  "$SYS/log/curfeed.log" "$SYS/log/curfeed-close-tabs.log" "$SYS/hosts.before-curfeed" "$DATA/state"
check_kept "curfeed と関係ないファイルは消さない" $UNRELATED
check "README を見に行かせない" "$(grep -c 'README' "$WORK/stdout")" 0
check "残したものを消すコマンドを1行で表示する" "$(grep -c '^  sudo rm -rf ' "$WORK/stdout")" 1
check "Chrome の操作許可の外し方を案内する" "$(grep -c 'オートメーション' "$WORK/stdout")" 1
command_line=$(grep '^  sudo rm -rf ' "$WORK/stdout")
sh -c "${command_line#*sudo }"
check_gone "表示されたコマンドを実行すると、残したものがすべて消える" "$SYS/etc/curfeed" "$SYS/log/curfeed.log" \
  "$SYS/log/curfeed-close-tabs.log" "$SYS/hosts.before-curfeed" "$DATA"
check_kept "表示されたコマンドは curfeed と関係ないファイルを消さない" $UNRELATED

setup; rm "$SYS/log/curfeed.log" "$SYS/log/curfeed-close-tabs.log"; run
check "無いものはコマンドに含めない" "$(grep '^  sudo rm -rf ' "$WORK/stdout" | grep -c 'curfeed.log')" 0
setup; rm -rf "$SYS/etc/curfeed" "$SYS/log/curfeed.log" "$SYS/log/curfeed-close-tabs.log" "$SYS/hosts.before-curfeed" "$DATA"; run
check "何も残っていなければ消すコマンドは表示しない" "$(grep -c 'sudo rm' "$WORK/stdout")" 0

echo "--purge"
setup; run --purge; status=$?
check "終了コード 0" "$status" 0
check_gone "本体と launchd の設定を削除する" $PROGRAM
check_gone "設定・ログ・元の hosts・状態の記録も削除する" "$SYS/etc/curfeed" "$SYS/log/curfeed.log" \
  "$SYS/log/curfeed-close-tabs.log" "$SYS/hosts.before-curfeed" "$DATA"
check "hosts からブロック区間だけを取り除く" "$(cat "$SYS/hosts")" "$EXPECTED_HOSTS"
check_kept "curfeed と関係ないファイルは消さない" $UNRELATED
check "消すコマンドは表示しない" "$(grep -c 'sudo rm' "$WORK/stdout")" 0
check "Chrome の操作許可の外し方は案内する" "$(grep -c 'オートメーション' "$WORK/stdout")" 1

echo "異常系（何も消さずにエラー終了する）"
setup; STUB_UID=501 run; status=$?
check "root でなければ終了コードが 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero
check_kept "root でなければ何も消さない" $PROGRAM "$SYS/etc/curfeed"
setup; run --force; status=$?
check "不明なオプションは終了コードが 0 以外" "$([ "$status" -ne 0 ] && echo nonzero)" nonzero
check_kept "不明なオプションのときは何も消さない" $PROGRAM "$SYS/etc/curfeed"

finish
