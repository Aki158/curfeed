#!/bin/sh
# シェルスクリプトの書き方のテスト。
# macOS の /bin/sh（bash 3.2）は UTF-8 の言語設定のとき、"$変数（" のように変数名の直後に
# 日本語などの ASCII 以外の文字が続くと、その文字の一部まで変数名として読んでしまう。
# そのため変数名の直後に ASCII 以外の文字を書くときは "${変数}（" と書く

. "$(dirname "$0")/helpers.sh"

# 引数: ファイル...。変数名の直後に ASCII 以外の文字が続く行を「ファイル:行番号:内容」で出す
find_unbraced() {
  LC_ALL=C grep -n -E '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:space:]]' "$@"
}

echo "変数名の直後の文字"
# 悪い例は、このファイル自体が検出されないよう、全角かっこを後から差し込んで作る
printf 'echo "$name%s説明%s"\n' '（' '）' > "$WORK/bad.sh"
printf 'echo "${name}（説明）" "$name です"\n' > "$WORK/good.sh"
check "検出できる: \"\$変数（\" の書き方" "$(find_unbraced "$WORK/bad.sh" | wc -l | tr -d ' ')" 1
check "検出しない: \"\${変数}（\" と \"\$変数 \" の書き方" "$(find_unbraced "$WORK/good.sh" | wc -l | tr -d ' ')" 0

found=$(cd "$ROOT" && find_unbraced bin/curfeed libexec/curfeed/* install.sh uninstall.sh tests/*.sh)
check "リポジトリのスクリプトに \"\$変数（\" の書き方が無い" "$found" ""

finish
