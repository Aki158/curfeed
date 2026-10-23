#!/bin/sh
# すべてのテストを実行する。実行: sh tests/run.sh（または make test）
# 言語設定によって sh の動きが変わることがあるので、英語（C）と日本語（UTF-8）の両方で実行する

cd "$(dirname "$0")"
failed=""
for locale in C ja_JP.UTF-8; do
  for t in test_*.sh; do
    echo "== ${t}（LC_ALL=${locale}）"
    LC_ALL=$locale sh "$t" || failed="$failed $t($locale)"
    echo
  done
done

if [ -n "$failed" ]; then
  echo "失敗したテストがあります:$failed"
  exit 1
fi
echo "すべてのテストが成功しました"
