#!/bin/sh
# すべてのテストを実行する。実行: sh tests/run.sh（または make test）

cd "$(dirname "$0")"
failed=""
for t in test_*.sh; do
  echo "== $t"
  sh "$t" || failed="$failed $t"
  echo
done

if [ -n "$failed" ]; then
  echo "失敗したテストがあります:$failed"
  exit 1
fi
echo "すべてのテストが成功しました"
