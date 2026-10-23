#!/bin/sh
# curfeed をインストールして launchd に登録する。実行: sudo ./install.sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "sudo ./install.sh で実行してください" >&2; exit 1; }
cd "$(dirname "$0")"

PREFIX=/usr/local
ETC=$PREFIX/etc/curfeed
LIBEXEC=$PREFIX/libexec/curfeed
DAEMON_LABEL=local.curfeed
DAEMON_PLIST=/Library/LaunchDaemons/$DAEMON_LABEL.plist
AGENT_LABEL=local.curfeed.close-tabs
AGENT_PLIST=/Library/LaunchAgents/$AGENT_LABEL.plist
APPLY_LOG=/var/log/curfeed.log
AGENT_LOG=/var/log/curfeed-close-tabs.log
console_uid=$(stat -f %u /dev/console)
CURFEED_ETC=$ETC
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
# 再インストール時は、編集済みの設定をそのまま使う
init_settings
chmod 644 "$CURFEED_CONFIG" "$CURFEED_BLOCKLIST"

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
echo "  設定:   $ETC/（curfeed add / remove / set-time で変更できます）"
echo "  初めての場合は、ブロックするサイトと許可時間帯を決めてください:"
echo "    curfeed add youtube.com www.youtube.com"
echo "    curfeed set-time 21:00-22:00"
echo "  ログ:   curfeed log"
echo "  アンインストール:   curfeed uninstall"
echo "  ※ 初めてのときだけ、ブロック中に Chrome を開いていると「Google Chrome を制御しようとしています」"
echo "     という確認が出ます（インストール直後ではなく、ブロックが始まったときに出ることもあります）。"
echo "     開いたままのタブを閉じるのに使うので「OK」を押してください。"
echo "     あとから システム設定 > プライバシーとセキュリティ > オートメーション でも変えられます。"
echo
# 最初の切り替えが終わってから状態を表示する
sleep 2
"$PREFIX/bin/curfeed" status
