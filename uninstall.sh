#!/bin/sh
# curfew を停止・削除し、hosts からブロック区間を取り除く。実行: sudo ./uninstall.sh
# 設定（/usr/local/etc/curfew）とログは残す
set -eu

[ "$(id -u)" -eq 0 ] || { echo "sudo を付けて実行してください" >&2; exit 1; }

DAEMON_PLIST=/Library/LaunchDaemons/local.curfew.plist
AGENT_PLIST=/Library/LaunchAgents/local.curfew.close-tabs.plist
console_uid=$(stat -f %u /dev/console)

launchctl bootout "gui/$console_uid" "$AGENT_PLIST" 2> /dev/null || true
launchctl bootout system "$DAEMON_PLIST" 2> /dev/null || true
rm -f "$DAEMON_PLIST" "$AGENT_PLIST" /usr/local/bin/curfew
rm -rf /usr/local/libexec/curfew
sed -i '' '/^# >>> curfew >>>$/,/^# <<< curfew <<<$/d' /etc/hosts
dscacheutil -flushcache
killall -HUP mDNSResponder

echo "curfew を削除しました"
echo "次のものは残しています（不要なら手動で削除してください）:"
echo "  設定:             /usr/local/etc/curfew/"
echo "  ログ:             /var/log/curfew.log /var/log/curfew-close-tabs.log"
echo "  元の hosts:       /etc/hosts.before-curfew"
echo "  状態の記録:       ~/Library/Application Support/curfew/"
echo "完全に消すコマンドは README の「アンインストール後に残るもの」にあります"
