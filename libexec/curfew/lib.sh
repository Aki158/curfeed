# curfew の各スクリプトで共有する設定と関数。sh で読み込んで使う
#
# 環境変数で上書きできる値:
#   CURFEW_ETC      設定の置き場所（config / blocklist）
#   CURFEW_HOSTS    書き換える hosts ファイル
#   CURFEW_LOG_DIR  ログの置き場所
#   CURFEW_DATA     タブを閉じる側が前回の状態を記録する場所
#   CURFEW_NOW      現在時刻 HHMM

CURFEW_ETC="${CURFEW_ETC:-/usr/local/etc/curfew}"
CURFEW_HOSTS="${CURFEW_HOSTS:-/etc/hosts}"
CURFEW_LOG_DIR="${CURFEW_LOG_DIR:-/var/log}"
CURFEW_CONFIG="$CURFEW_ETC/config"
CURFEW_BLOCKLIST="$CURFEW_ETC/blocklist"
CURFEW_APPLY_LOG="$CURFEW_LOG_DIR/curfew.log"
CURFEW_CLOSE_TABS_LOG="$CURFEW_LOG_DIR/curfew-close-tabs.log"
CURFEW_BEGIN_MARK='# >>> curfew >>>'
CURFEW_END_MARK='# <<< curfew <<<'
# 初期値は 24 時間許可（何もブロックしない）。使う人が curfew set-time で許可時間帯を決める
CURFEW_DEFAULT_START=0000
CURFEW_DEFAULT_END=2400

stamp() {
  date '+%Y-%m-%d %H:%M'
}

curfew_now() {
  echo "${CURFEW_NOW:-$(date +%H%M)}"
}

# root の LaunchDaemon には HOME が無いので、使うときにだけ決める
curfew_data_dir() {
  echo "${CURFEW_DATA:-$HOME/Library/Application Support/curfew}"
}

# HHMM を 0:00 からの分に変換する。不正な値なら失敗する
to_minutes() {
  case $1 in
    [0-2][0-9][0-5][0-9]) ;;
    *) return 1 ;;
  esac
  _h=${1%??}
  _m=${1#??}
  # 先頭の 0 を外して 8 進数扱いを避ける
  _h=${_h#0}
  _m=${_m#0}
  [ "$_h" -lt 24 ] || { [ "$_h" -eq 24 ] && [ "$_m" -eq 0 ]; } || return 1
  echo $((_h * 60 + _m))
}

# HH:MM / HHMM を HHMM にそろえる。不正な値なら失敗する
normalize_time() {
  case $1 in
    [0-9][0-9]:[0-9][0-9]) _t="${1%:*}${1#*:}" ;;
    *) _t=$1 ;;
  esac
  to_minutes "$_t" > /dev/null || return 1
  echo "$_t"
}

# HHMM を HH:MM で表示する
format_time() {
  echo "${1%??}:${1#??}"
}

# 許可時間帯を config に書く。引数: 開始 終了（HHMM）
write_config() {
  cat > "$CURFEW_CONFIG" << EOF
# curfew の設定（curfew set-time で変更できます）
# 許可時間帯: ALLOW_START から ALLOW_END の直前まで（HHMM）。終了が開始より前なら日付をまたぐ
ALLOW_START=$1
ALLOW_END=$2
EOF
}

# 設定が無ければ初期値（24 時間許可、ブロック対象なし）で作る。既にある設定は変えない
init_settings() {
  mkdir -p "$CURFEW_ETC"
  [ -e "$CURFEW_CONFIG" ] || write_config "$CURFEW_DEFAULT_START" "$CURFEW_DEFAULT_END"
  if [ ! -e "$CURFEW_BLOCKLIST" ]; then
    cat > "$CURFEW_BLOCKLIST" << 'EOF'
# 許可時間帯以外にブロックするドメイン。1行1ドメイン、# 以降はコメント
# curfew add youtube.com のように登録します（curfew remove で削除）。www. の有無は別のドメインとして扱います
EOF
  fi
}

# config から許可時間帯を読み、allow_start / allow_end（HHMM）に入れる。
# 失敗したら理由を curfew_error に入れて失敗する
load_window() {
  if [ ! -r "$CURFEW_CONFIG" ]; then
    curfew_error="設定ファイルを読めません: $CURFEW_CONFIG"
    return 1
  fi
  allow_start=$(sed -n 's/^ALLOW_START=//p' "$CURFEW_CONFIG" | tail -n 1)
  allow_end=$(sed -n 's/^ALLOW_END=//p' "$CURFEW_CONFIG" | tail -n 1)
  if ! to_minutes "$allow_start" > /dev/null; then
    curfew_error="ALLOW_START が不正です: '$allow_start'（$CURFEW_CONFIG）"
    return 1
  fi
  if ! to_minutes "$allow_end" > /dev/null; then
    curfew_error="ALLOW_END が不正です: '$allow_end'（$CURFEW_CONFIG）"
    return 1
  fi
}

# 引数: 現在 開始 終了（HHMM）。現在が許可時間帯なら成功する。終了が開始より前なら日付をまたぐ
in_window() {
  _now=$(to_minutes "$1")
  _start=$(to_minutes "$2")
  _end=$(to_minutes "$3")
  if [ "$_start" -le "$_end" ]; then
    [ "$_now" -ge "$_start" ] && [ "$_now" -lt "$_end" ]
  else
    [ "$_now" -ge "$_start" ] || [ "$_now" -lt "$_end" ]
  fi
}

# 引数: 開始 終了（HHMM）。許可時間帯が 24 時間（00:00〜24:00）なら成功する
is_full_day() {
  [ "$(to_minutes "$1")" -eq 0 ] && [ "$(to_minutes "$2")" -eq 1440 ]
}

# blocklist のドメインを1行ずつ出す（# 以降と空行は除く）
blocklist_domains() {
  awk '{ sub(/#.*/, ""); if (NF) print $1 }' "$CURFEW_BLOCKLIST"
}

valid_domain() {
  case $1 in
    '' | *[!A-Za-z0-9.-]* | .* | *. | *..*) return 1 ;;
    *.*) return 0 ;;
    *) return 1 ;;
  esac
}

# hosts のブロック区間に書かれたホストを出す。区間が無ければ何も出さない
blocked_hosts() {
  awk -v b="$CURFEW_BEGIN_MARK" -v e="$CURFEW_END_MARK" '
    $0 == b { inside = 1; next }
    $0 == e { inside = 0; next }
    inside && $1 == "0.0.0.0" { print tolower($2) }
  ' "$CURFEW_HOSTS"
}
