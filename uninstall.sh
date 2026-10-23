#!/bin/sh
# curfeed を停止・削除し、hosts からブロック区間を取り除く。実行: sudo ./uninstall.sh
# 設定（/usr/local/etc/curfeed）とログは残す
set -eu

[ "$(id -u)" -eq 0 ] || { echo "sudo を付けて実行してください" >&2; exit 1; }

DAEMON_PLIST=/Library/LaunchDaemons/local.curfeed.plist
AGENT_PLIST=/Library/LaunchAgents/local.curfeed.close-tabs.plist
console_uid=$(stat -f %u /dev/console)

launchctl bootout "gui/$console_uid" "$AGENT_PLIST" 2> /dev/null || true
launchctl bootout system "$DAEMON_PLIST" 2> /dev/null || true
rm -f "$DAEMON_PLIST" "$AGENT_PLIST" /usr/local/bin/curfeed
rm -rf /usr/local/libexec/curfeed
sed -i '' '/^# >>> curfeed >>>$/,/^# <<< curfeed <<<$/d' /etc/hosts
dscacheutil -flushcache
killall -HUP mDNSResponder

echo "curfeed を削除しました"
echo "次のものは残しています（不要なら手動で削除してください）:"
echo "  設定:             /usr/local/etc/curfeed/"
echo "  ログ:             /var/log/curfeed.log /var/log/curfeed-close-tabs.log"
echo "  元の hosts:       /etc/hosts.before-curfeed"
echo "  状態の記録:       ~/Library/Application Support/curfeed/"
echo "完全に消すコマンドは README の「アンインストール後に残るもの」にあります"
