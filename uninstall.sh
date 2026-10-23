#!/bin/sh
# curfeed をアンインストールする（ジョブを止めて本体を削除し、hosts からブロック区間を取り除く）。
# 実行: sudo ./uninstall.sh [--purge]
# 通常は設定・ログ・元の hosts の退避ファイルを残し（入れ直したときに引き継ぐ）、
# それらを消すためのコマンドを表示する。--purge を付けると、それらもすべて削除する
#
# 環境変数で上書きできる値（lib.sh のものに加えて）:
#   CURFEED_PREFIX   本体を置いた場所（既定 /usr/local）
#   CURFEED_LIBRARY  launchd の設定を置いた場所（既定 /Library）
set -eu

purge=0
case ${1:-} in
  '') ;;
  --purge) purge=1 ;;
  *)
    echo "不明なオプションです: $1（使えるのは --purge だけです）" >&2
    exit 1
    ;;
esac
[ "$(id -u)" -eq 0 ] || { echo "sudo を付けて実行してください" >&2; exit 1; }

# リポジトリから実行したときと、インストール先（libexec/curfeed）から実行したときの両方に対応する
here=$(dirname "$0")
if [ -r "$here/lib.sh" ]; then
  . "$here/lib.sh"
else
  . "$here/libexec/curfeed/lib.sh"
fi

PREFIX=${CURFEED_PREFIX:-/usr/local}
LIBRARY=${CURFEED_LIBRARY:-/Library}
DAEMON_PLIST=$LIBRARY/LaunchDaemons/local.curfeed.plist
AGENT_PLIST=$LIBRARY/LaunchAgents/local.curfeed.close-tabs.plist
console_uid=$(stat -f %u /dev/console)
# sudo で実行していても、ログイン中のユーザーの状態の記録を対象にする
if [ -n "${CURFEED_DATA:-}" ]; then
  data_dir=$CURFEED_DATA
else
  console_home=$(dscl . -read "/Users/$(stat -f %Su /dev/console)" NFSHomeDirectory | awk '{ print $2 }')
  data_dir=${console_home:+$console_home/Library/Application Support/curfeed}
fi

# 残っている設定などを「表示名|パス」の形で1行ずつ出す
leftovers() {
  for entry in "設定|$CURFEED_ETC" "ログ|$CURFEED_APPLY_LOG" "ログ|$CURFEED_CLOSE_TABS_LOG" \
    "元の hosts|$CURFEED_HOSTS_BACKUP"; do
    if [ -n "${entry#*|}" ] && [ -e "${entry#*|}" ]; then
      printf '%s\n' "$entry"
    fi
  done
}

launchctl bootout "gui/$console_uid" "$AGENT_PLIST" 2> /dev/null || true
launchctl bootout system "$DAEMON_PLIST" 2> /dev/null || true
rm -f "$DAEMON_PLIST" "$AGENT_PLIST" "$PREFIX/bin/curfeed"
rm -rf "$PREFIX/libexec/curfeed"

# hosts のブロック区間を取り除く。ファイルの所有者や権限を変えないよう、中身だけを書き換える
tmp=$(mktemp)
awk -v b="$CURFEED_BEGIN_MARK" -v e="$CURFEED_END_MARK" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip
' "$CURFEED_HOSTS" > "$tmp"
cat "$tmp" > "$CURFEED_HOSTS"
rm -f "$tmp"
dscacheutil -flushcache 2> /dev/null || true
killall -HUP mDNSResponder 2> /dev/null || true

# タブを閉じる仕組みが使う「前回の状態の記録」は、動いている間だけ意味があるので必ず消す。
# 残すと、入れ直したときに「ずっとブロック中だった」と判断され、Chrome の接続のリセットが行われない
if [ -n "$data_dir" ]; then
  rm -rf -- "$data_dir"
fi

echo "curfeed をアンインストールしました"
if [ "$purge" -eq 1 ]; then
  leftovers | while IFS='|' read -r label path; do
    rm -rf -- "$path"
    echo "  削除しました（${label}）: $path"
  done
elif [ -n "$(leftovers)" ]; then
  echo "次のものは残しています（入れ直したときに引き継ぎます）:"
  leftovers | while IFS='|' read -r label path; do
    echo "  ${label}: $path"
  done
  echo "すべて消す場合は、次のコマンドを実行してください:"
  printf '  sudo rm -rf'
  leftovers | while IFS='|' read -r label path; do
    printf " '%s'" "$path"
  done
  echo
fi
echo "Chrome を操作する許可は、システム設定 > プライバシーとセキュリティ > オートメーション でオフにできます"
