#!/bin/sh
# curfew をインストールして launchd に登録する。実行: sudo ./install.sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "sudo ./install.sh で実行してください" >&2; exit 1; }
cd "$(dirname "$0")"

PREFIX=/usr/local
ETC=$PREFIX/etc/curfew
LIBEXEC=$PREFIX/libexec/curfew
DAEMON_LABEL=local.curfew
DAEMON_PLIST=/Library/LaunchDaemons/$DAEMON_LABEL.plist
AGENT_LABEL=local.curfew.close-tabs
AGENT_PLIST=/Library/LaunchAgents/$AGENT_LABEL.plist
APPLY_LOG=/var/log/curfew.log
AGENT_LOG=/var/log/curfew-close-tabs.log
console_uid=$(stat -f %u /dev/console)

# 初回だけ元の hosts を退避する
[ -e /etc/hosts.before-curfew ] || cp -p /etc/hosts /etc/hosts.before-curfew

mkdir -p "$PREFIX/bin" "$LIBEXEC"
install -m 755 -o root -g wheel bin/curfew "$PREFIX/bin/curfew"
install -m 644 -o root -g wheel libexec/curfew/lib.sh "$LIBEXEC/lib.sh"
install -m 755 -o root -g wheel libexec/curfew/apply "$LIBEXEC/apply"
install -m 755 -o root -g wheel libexec/curfew/close-tabs "$LIBEXEC/close-tabs"
install -m 755 -o root -g wheel uninstall.sh "$LIBEXEC/uninstall.sh"

# 設定が無ければ初期値（24 時間許可、ブロック対象なし）で作る。
# 再インストール時は、編集済みの設定をそのまま使う
CURFEW_ETC=$ETC
. "$LIBEXEC/lib.sh"
init_settings
chmod 644 "$CURFEW_CONFIG" "$CURFEW_BLOCKLIST"

install -m 644 -o root -g wheel "launchd/$DAEMON_LABEL.plist" "$DAEMON_PLIST"
install -m 644 -o root -g wheel "launchd/$AGENT_LABEL.plist" "$AGENT_PLIST"

touch "$APPLY_LOG" "$AGENT_LOG"
chmod 644 "$APPLY_LOG" "$AGENT_LOG"
# タブを閉じるジョブはログイン中のユーザーの権限で動くので、そのユーザーが書けるようにする
chown "$console_uid" "$AGENT_LOG"

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
echo "インストールしました"
echo "  設定:   $ETC/（curfew add / remove / set-time で変更できます）"
echo "  初めての場合は、ブロックするサイトと許可時間帯を決めてください:"
echo "    curfew add youtube.com www.youtube.com"
echo "    curfew set-time 21:00 22:00"
echo "  ログ:   curfew log"
echo "  削除:   curfew uninstall"
echo "Chrome の操作許可を求められたら「OK」を押してください"
echo
# 最初の切り替えが終わってから状態を表示する
sleep 2
"$PREFIX/bin/curfew" status
