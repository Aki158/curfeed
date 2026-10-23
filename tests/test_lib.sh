#!/bin/sh
# libexec/curfeed/lib.sh のうち、設定の初期化（init_settings）と許可時間帯の扱い
# （load_windows / merge_windows）のテスト。一時ディレクトリを設定の置き場所にして読み込む

. "$(dirname "$0")/helpers.sh"

# 引数: 実行するシェルのコード。lib.sh を読み込んだうえで実行する
in_lib() {
  CURFEED_ETC="$WORK/etc" sh -c ". \"$ROOT/libexec/curfeed/lib.sh\"; $1" > "$WORK/stdout" 2> "$WORK/stderr"
}

# 引数: テスト名 入力（"HHMM-HHMM" を空白区切り） 期待する結果
check_merge() {
  in_lib "merge_windows '$2'"
  check "$1" "$(cat "$WORK/stdout")" "$3"
}

# 引数: config の中身。load_windows を実行し、結果を stdout に、終了コードを返す
load_config() {
  mkdir -p "$WORK/etc"
  printf '%s\n' "$1" > "$WORK/etc/config"
  in_lib 'load_windows || { echo "$curfeed_error" >&2; exit 1; }; echo "$allow_windows"'
}

echo "init_settings（設定が無いとき）"
rm -rf "$WORK/etc"
in_lib init_settings; status=$?
check "終了コード 0" "$status" 0
in_lib 'load_windows && echo "$allow_windows"'
check "許可時間帯の初期値は 24 時間（00:00〜24:00）" "$(cat "$WORK/stdout")" "0000-2400"
in_lib 'blocklist_domains | wc -l | tr -d " "'
check "ブロック対象は空で作る" "$(cat "$WORK/stdout")" 0
check "blocklist に登録方法の案内を書く" "$(grep -c 'curfeed add' "$WORK/etc/blocklist")" 1

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

echo "merge_windows（重なり・つながりをまとめる）"
check_merge "重ならない時間帯はそのまま" "1200-1300 2100-2200" "1200-1300 2100-2200"
check_merge "開始時刻の順に並べる" "2100-2200 1200-1300" "1200-1300 2100-2200"
check_merge "重なる時間帯は1つにまとめる" "1200-1400 1300-1500" "1200-1500"
check_merge "つながる時間帯は1つにまとめる" "1200-1300 1300-1400" "1200-1400"
check_merge "内側に含まれる時間帯は外側にまとめる" "1000-1800 1200-1300" "1000-1800"
check_merge "日付をまたぐ時間帯はそのまま" "2300-0100" "2300-0100"
check_merge "0時をはさんでつながる時間帯は、日付をまたぐ1つにまとめる" "0000-0100 2300-2400" "2300-0100"
check_merge "日付をまたぐ時間帯は最後に並べる" "2300-0100 1200-1300" "1200-1300 2300-0100"
check_merge "1日をすき間なく覆えば 24 時間になる" "0000-1200 1200-2400" "0000-2400"
check_merge "終了 00:00 は 24:00 として扱う" "2200-0000" "2200-2400"

echo "load_windows（config の読み方）"
load_config 'ALLOW=1200-1300,2100-2200'; status=$?
check "ALLOW をカンマ区切りで読む" "$(cat "$WORK/stdout")" "1200-1300 2100-2200"
load_config 'ALLOW=2100-2200,1200-1400,1300-1500'
check "読むときも重なりをまとめて並べる" "$(cat "$WORK/stdout")" "1200-1500 2100-2200"
load_config "ALLOW_START=2100
ALLOW_END=2200"
check "以前の形式（ALLOW_START / ALLOW_END）も読める" "$(cat "$WORK/stdout")" "2100-2200"
load_config "ALLOW_START=0700
ALLOW_END=0800
ALLOW=2100-2200"
check "両方あれば ALLOW を使う" "$(cat "$WORK/stdout")" "2100-2200"
load_config "ALLOW=1200-1300
ALLOW=2100-2200"
check "ALLOW が複数行あれば最後の行を使う" "$(cat "$WORK/stdout")" "2100-2200"
for bad in 'ALLOW=1200-2500' 'ALLOW=1200' 'ALLOW=1200-1200' 'ALLOW=2400-0100' 'ALLOW=12:00-13:00' 'ALLOW=' '# 何もない'; do
  load_config "$bad"; status=$?
  if [ "$status" -ne 0 ] && grep -q '許可時間帯' "$WORK/stderr"; then
    ok "不正な設定（${bad}）は理由を付けて失敗する"
  else
    ng "不正な設定（${bad}）は理由を付けて失敗する" "status=$status stdout=$(cat "$WORK/stdout") stderr=$(cat "$WORK/stderr")"
  fi
done

finish
