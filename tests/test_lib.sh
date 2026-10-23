#!/bin/sh
# libexec/curfew/lib.sh のうち、インストール時に使う init_settings のテスト。
# 一時ディレクトリを設定の置き場所にして読み込む

. "$(dirname "$0")/helpers.sh"

# 引数: 実行するシェルのコード。lib.sh を読み込んだうえで実行する
in_lib() {
  CURFEW_ETC="$WORK/etc" sh -c ". \"$ROOT/libexec/curfew/lib.sh\"; $1" > "$WORK/stdout" 2> "$WORK/stderr"
}

echo "init_settings（設定が無いとき）"
rm -rf "$WORK/etc"
in_lib init_settings; status=$?
check "終了コード 0" "$status" 0
in_lib 'load_window && echo "$allow_start $allow_end"'
check "許可時間帯の初期値は 24 時間（00:00〜24:00）" "$(cat "$WORK/stdout")" "0000 2400"
in_lib 'blocklist_domains | wc -l | tr -d " "'
check "ブロック対象は空で作る" "$(cat "$WORK/stdout")" 0
check "blocklist に登録方法の案内を書く" "$(grep -c 'curfew add' "$WORK/etc/blocklist")" 1

echo "init_settings（設定が既にあるとき）"
mkdir -p "$WORK/etc"
printf 'ALLOW_START=0700\nALLOW_END=0800\n' > "$WORK/etc/config"
printf 'x.com\n' > "$WORK/etc/blocklist"
in_lib init_settings
check "既存の config を上書きしない" "$(cat "$WORK/etc/config")" "ALLOW_START=0700
ALLOW_END=0800"
check "既存の blocklist を上書きしない" "$(cat "$WORK/etc/blocklist")" "x.com"
rm "$WORK/etc/blocklist"
in_lib init_settings
check "片方だけ無ければ、無い方だけ作る（config はそのまま）" "$(grep '^ALLOW_START=' "$WORK/etc/config")" "ALLOW_START=0700"
check "片方だけ無ければ、無い方だけ作る（blocklist を作る）" "$([ -e "$WORK/etc/blocklist" ] && echo yes)" yes

finish
