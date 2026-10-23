# テスト共通の関数。各テストから `. "$(dirname "$0")/helpers.sh"` で読み込む

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

ng() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  [ -z "${2:-}" ] || printf '       %s\n' "$2"
}

# 引数: テスト名 実際の値 期待する値
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else ng "$1" "期待: [$3] 実際: [$2]"; fi
}

# 引数: テスト名 ファイル 含まれるべき行（完全一致）
check_has_line() {
  if grep -qxF -- "$3" "$2" 2>/dev/null; then ok "$1"; else ng "$1" "[$3] がありません"; fi
}

# 引数: テスト名 ファイル 含まれてはいけない行（完全一致）
check_no_line() {
  if grep -qxF -- "$3" "$2" 2>/dev/null; then ng "$1" "[$3] があります"; else ok "$1"; fi
}

finish() {
  echo
  echo "結果: ${PASS} passed, ${FAIL} failed"
  [ "$FAIL" -eq 0 ]
}
