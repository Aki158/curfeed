#!/bin/sh
# curfeed をインストールして launchd に登録する。実行: sudo ./install.sh
#
# 環境変数で上書きできる値（lib.sh のものに加えて）:
#   CURFEED_PREFIX   本体を置く場所（既定 /usr/local）
#   CURFEED_LIBRARY  launchd の設定を置く場所（既定 /Library）
set -eu

[ "$(id -u)" -eq 0 ] || { echo "sudo ./install.sh で実行してください" >&2; exit 1; }
cd "$(dirname "$0")"

PREFIX=${CURFEED_PREFIX:-/usr/local}
LIBRARY=${CURFEED_LIBRARY:-/Library}
LIBEXEC=$PREFIX/libexec/curfeed
DAEMON_LABEL=local.curfeed
DAEMON_PLIST=$LIBRARY/LaunchDaemons/$DAEMON_LABEL.plist
AGENT_LABEL=local.curfeed.close-tabs
AGENT_PLIST=$LIBRARY/LaunchAgents/$AGENT_LABEL.plist
console_uid=$(stat -f %u /dev/console)
# 設定・ログ・hosts の置き場所は lib.sh の値を使う
. libexec/curfeed/lib.sh

# 初回だけ元の hosts を退避する
[ -e "$CURFEED_HOSTS_BACKUP" ] || cp -p "$CURFEED_HOSTS" "$CURFEED_HOSTS_BACKUP"

mkdir -p "$PREFIX/bin" "$LIBEXEC"
install -m 755 -o root -g wheel bin/curfeed "$PREFIX/bin/curfeed"
install -m 644 -o root -g wheel libexec/curfeed/lib.sh "$LIBEXEC/lib.sh"
install -m 755 -o root -g wheel libexec/curfeed/apply "$LIBEXEC/apply"
install -m 755 -o root -g wheel libexec/curfeed/close-tabs "$LIBEXEC/close-tabs"
install -m 755 -o root -g wheel uninstall.sh "$LIBEXEC/uninstall.sh"

# 設定が無ければ初期値（24 時間許可、ブロック対象なし）で作る。
# 再インストール時は、編集済みの設定をそのまま使う。
# 設定が無いときを初めてのインストール（--purge でアンインストールしたあとも含む）とみなし、表示を変える
if [ -e "$CURFEED_CONFIG" ]; then first_install=0; else first_install=1; fi
init_settings
chmod 644 "$CURFEED_CONFIG" "$CURFEED_BLOCKLIST"

install -m 644 -o root -g wheel "launchd/$DAEMON_LABEL.plist" "$DAEMON_PLIST"
install -m 644 -o root -g wheel "launchd/$AGENT_LABEL.plist" "$AGENT_PLIST"

touch "$CURFEED_APPLY_LOG" "$CURFEED_CLOSE_TABS_LOG"
chmod 644 "$CURFEED_APPLY_LOG" "$CURFEED_CLOSE_TABS_LOG"
# タブを閉じるジョブはログイン中のユーザーの権限で動くので、そのユーザーが書けるようにする
chown "$console_uid" "$CURFEED_CLOSE_TABS_LOG"

# hosts を書き換える root のジョブ
if launchctl print "system/$DAEMON_LABEL" > /dev/null 2>&1; then
  launchctl bootout system "$DAEMON_PLIST"
  sleep 1
fi
launchctl bootstrap system "$DAEMON_PLIST"

# Chrome のタブを閉じるジョブは、ログイン中のユーザーの権限で動かす
if [ "$console_uid" -ne 0 ]; then
  if launchctl print "gui/$console_uid/$AGENT_LABEL" > /dev/null 2>&1; then
    launchctl bootout "gui/$console_uid" "$AGENT_PLIST"
    sleep 1
  fi
  launchctl bootstrap "gui/$console_uid" "$AGENT_PLIST"
fi

echo
if [ "$first_install" -eq 1 ]; then
  echo "インストールしました"
  echo
  echo "※ ブロック中に Chrome を開いていると、初めてのときだけ「Google Chrome を制御しようとしています」と出ます。"
  echo "   開いたままのタブを閉じるのに使うので「OK」を押してください。"
  echo "※ Chrome を使う場合は、README の「Chrome の QUIC（HTTP/3）を止める」も行ってください。"
else
  echo "インストールしました（設定は引き継いでいます）"
fi
echo "使い方: curfeed help"
echo
# 最初の切り替えが終わってから状態を表示する。
# 次にやること（ブロックするサイトと許可時間帯を決める）は、まだ決めていなければ status が案内する
sleep 2
"$PREFIX/bin/curfeed" status
