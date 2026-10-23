#!/bin/sh
# libexec/curfew/apply のテスト。一時ディレクトリの hosts / 設定を使い、/etc/hosts には触れない

. "$(dirname "$0")/helpers.sh"

ORIGINAL_HOSTS='##
# Host Database
##
127.0.0.1	localhost
255.255.255.255	broadcasthost
::1             localhost

# 手で書いたコメント
#127.0.0.1       www.youtube.com
'

# 引数: [許可開始 許可終了]
setup() {
  mkdir -p "$WORK/etc"
  printf '%s' "$ORIGINAL_HOSTS" > "$WORK/hosts"
  printf '%s\n' '# SNS' 'www.youtube.com' '' '  x.com   # 行末コメント' > "$WORK/etc/blocklist"
  printf 'ALLOW_START=%s\nALLOW_END=%s\n' "${1:-2100}" "${2:-2200}" > "$WORK/etc/config"
}

# 引数: 現在時刻 HHMM。終了コードを返す
run() {
  CURFEW_ETC="$WORK/etc" CURFEW_HOSTS="$WORK/hosts" CURFEW_NOW="$1" \
    sh "$ROOT/libexec/curfew/apply" > "$WORK/stdout" 2> "$WORK/stderr"
}

is_blocked() { grep -qx '0.0.0.0 www.youtube.com' "$WORK/hosts"; }

assert_blocked() {
  if is_blocked; then ok "$1"; else ng "$1" "ブロック行がありません"; fi
}
assert_unblocked() {
  if ! is_blocked && ! grep -q 'curfew' "$WORK/hosts"; then ok "$1"; else ng "$1" "ブロック行が残っています"; fi
}

echo "時間帯の判定（許可 21:00-22:00）"
setup; run 2059; assert_blocked "20:59 は許可時間前なのでブロックする"
setup; run 2059; run 2100; assert_unblocked "21:00 ちょうどで解除する"
setup; run 2159; assert_unblocked "21:59 は許可時間内なので解除状態"
setup; run 2200; assert_blocked "22:00 ちょうどでブロックする"
setup; run 0030; assert_blocked "00:30（先頭ゼロ）でもブロックする"
setup; run 0900; assert_blocked "09:00（8進数と誤解釈されやすい値）でもブロックする"

echo "日付をまたぐ許可時間（23:00-01:00）"
setup 2300 0100; run 2259; assert_blocked "22:59 はブロック"
setup 2300 0100; run 2330; assert_unblocked "23:30 は許可"
setup 2300 0100; run 0030; assert_unblocked "00:30 は許可"
setup 2300 0100; run 0100; assert_blocked "01:00 ちょうどでブロック"

echo "24 時間許可（00:00-24:00）"
setup 0000 2400; run 0000; assert_unblocked "00:00 もブロックしない"
setup 0000 2400; run 1200; assert_unblocked "12:00 もブロックしない"
setup 0000 2400; run 2359; assert_unblocked "23:59 もブロックしない"
setup; run 2059; printf 'ALLOW_START=0000\nALLOW_END=2400\n' > "$WORK/etc/config"; run 2059
assert_unblocked "ブロック中に 24 時間許可へ変えたら解除する"

echo "hosts の書き換え内容"
setup; run 2059
check_has_line "IPv6 のブロック行も書く" "$WORK/hosts" ':: www.youtube.com'
check_has_line "行末コメント付きのドメインも読む" "$WORK/hosts" '0.0.0.0 x.com'
check "blocklist のコメント・空行は無視する（2ドメイン×2行=4行）" \
  "$(sed -n '/^# >>> curfew >>>$/,/^# <<< curfew <<<$/p' "$WORK/hosts" | grep -vc '^#')" 4
check "状態が変わったときはログを1行出す" "$(grep -c 'ブロックしました' "$WORK/stdout")" 1
run 2059; run 2300
check "繰り返し実行してもブロック区間が重複しない" "$(grep -c '^# >>> curfew >>>$' "$WORK/hosts")" 1
check "状態が変わらないときはログを出さない" "$(cat "$WORK/stdout")" ""
run 2130
if [ "$(cat "$WORK/hosts")" = "$(printf '%s' "$ORIGINAL_HOSTS")" ] \
  && [ "$(wc -c < "$WORK/hosts")" -eq "$(printf '%s' "$ORIGINAL_HOSTS" | wc -c)" ]; then
  ok "ブロック→解除で元の hosts と完全に一致する"
else
  ng "ブロック→解除で元の hosts と完全に一致する" "$(cat "$WORK/hosts")"
fi

setup; run 2059
printf '%s\n' 'www.youtube.com' > "$WORK/etc/blocklist"
run 2059
check_no_line "ブロック中に blocklist から消したドメインは hosts からも消える" "$WORK/hosts" '0.0.0.0 x.com'

echo "ブロック対象が空のとき"
setup; printf '# コメントだけ\n' > "$WORK/etc/blocklist"; run 2059
if [ "$(cat "$WORK/hosts")" = "$(printf '%s' "$ORIGINAL_HOSTS")" ]; then
  ok "ブロック時間でも hosts を変えない（空のブロック区間を作らない）"
else
  ng "ブロック時間でも hosts を変えない（空のブロック区間を作らない）" "$(cat "$WORK/hosts")"
fi
check "何もしていないのでログを出さない" "$(cat "$WORK/stdout")" ""
setup; run 2059; printf '# 全部消した\n' > "$WORK/etc/blocklist"; run 2059
assert_unblocked "ブロック中にドメインを全部消したらブロック区間を外す"
check "外したときは「解除しました」と記録する" "$(grep -c '解除しました' "$WORK/stdout")" 1

echo "設定ファイルの読み方"
setup; printf '# コメント\nALLOW_START=2100\nALLOW_END=2200\nALLOW_END=2300\n' > "$WORK/etc/config"
run 2230; assert_unblocked "同じキーが複数あれば最後の値を使う（22:30 は 21:00-23:00 の内側）"

echo "異常系（hosts を変更せずにエラー終了する）"
assert_error_unchanged() {
  name=$1
  shift
  before=$(cat "$WORK/hosts")
  if "$@"; then
    ng "$name" "終了コードが 0 でした"
  elif [ "$(cat "$WORK/hosts")" != "$before" ]; then
    ng "$name" "hosts が変更されました"
  elif ! grep -q 'curfew apply:' "$WORK/stderr"; then
    ng "$name" "エラーメッセージがありません: $(cat "$WORK/stderr")"
  else
    ok "$name"
  fi
}
setup; rm "$WORK/etc/blocklist"
assert_error_unchanged "blocklist が無い" run 2059
setup; printf '%s\n' 'https://www.youtube.com/' > "$WORK/etc/blocklist"
assert_error_unchanged "blocklist にドメイン以外（URL）が書かれている" run 2059
setup; rm "$WORK/etc/config"
assert_error_unchanged "config が無い" run 2059
setup 2500 2200
assert_error_unchanged "ALLOW_START が不正（2500）" run 2059
setup 2100 22:00
assert_error_unchanged "ALLOW_END が不正（22:00 形式）" run 2059
setup; printf 'ALLOW_START=2100\n' > "$WORK/etc/config"
assert_error_unchanged "ALLOW_END が無い" run 2059
setup; assert_error_unchanged "現在時刻が不正（2460）" run 2460
setup; assert_error_unchanged "現在時刻が不正（abc）" run abc
setup; printf '%s\n' '# >>> curfew >>>' '0.0.0.0 www.youtube.com' >> "$WORK/hosts"
assert_error_unchanged "hosts の開始マーカーに対応する終了マーカーが無い" run 2130
setup; run 2059
if grep -q '^20[0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9] ' "$WORK/stdout"; then
  ok "ログ行は日時から始まる"
else
  ng "ログ行は日時から始まる" "$(cat "$WORK/stdout")"
fi
setup; rm "$WORK/etc/blocklist"; run 2059
if grep -q '^20[0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9] curfew apply:' "$WORK/stderr"; then
  ok "エラー行も日時から始まる"
else
  ng "エラー行も日時から始まる" "$(cat "$WORK/stderr")"
fi

finish
