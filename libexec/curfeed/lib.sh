# curfeed の各スクリプトで共有する設定と関数。sh で読み込んで使う
#
# 環境変数で上書きできる値:
#   CURFEED_ETC      設定の置き場所（config / blocklist）
#   CURFEED_HOSTS    書き換える hosts ファイル
#   CURFEED_LOG_DIR  ログの置き場所
#   CURFEED_DATA     タブを閉じる側が前回の状態を記録する場所
#   CURFEED_NOW      現在時刻 HHMM

CURFEED_ETC="${CURFEED_ETC:-/usr/local/etc/curfeed}"
CURFEED_HOSTS="${CURFEED_HOSTS:-/etc/hosts}"
CURFEED_LOG_DIR="${CURFEED_LOG_DIR:-/var/log}"
CURFEED_HOSTS_BACKUP="$CURFEED_HOSTS.before-curfeed"
CURFEED_CONFIG="$CURFEED_ETC/config"
CURFEED_BLOCKLIST="$CURFEED_ETC/blocklist"
CURFEED_APPLY_LOG="$CURFEED_LOG_DIR/curfeed.log"
CURFEED_CLOSE_TABS_LOG="$CURFEED_LOG_DIR/curfeed-close-tabs.log"
CURFEED_BEGIN_MARK='# >>> curfeed >>>'
CURFEED_END_MARK='# <<< curfeed <<<'
# 初期値は 24 時間許可（何もブロックしない）。使う人が curfeed set-time で許可時間帯を決める
CURFEED_DEFAULT_WINDOWS=0000-2400

stamp() {
  date '+%Y-%m-%d %H:%M'
}

curfeed_now() {
  echo "${CURFEED_NOW:-$(date +%H%M)}"
}

# root の LaunchDaemon には HOME が無いので、使うときにだけ決める
curfeed_data_dir() {
  echo "${CURFEED_DATA:-$HOME/Library/Application Support/curfeed}"
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

# 許可時間帯は「開始-終了」（HHMM-HHMM）で表し、複数あるときは空白で区切って扱う。
# 終了が開始より前なら日付をまたぐ（例 2300-0100）

# 許可時間帯を config に書く。引数: 許可時間帯（空白区切り）
write_config() {
  cat > "$CURFEED_CONFIG" << EOF
# curfeed の設定（curfeed set-time で変更できます）
# 許可時間帯: 開始-終了（HHMM）をカンマ区切りで並べる。終了が開始より前なら日付をまたぐ
ALLOW=$(printf '%s' "$1" | tr ' ' ',')
EOF
}

# 設定が無ければ初期値（24 時間許可、ブロック対象なし）で作る。既にある設定は変えない
init_settings() {
  mkdir -p "$CURFEED_ETC"
  [ -e "$CURFEED_CONFIG" ] || write_config "$CURFEED_DEFAULT_WINDOWS"
  if [ ! -e "$CURFEED_BLOCKLIST" ]; then
    cat > "$CURFEED_BLOCKLIST" << 'EOF'
# 許可時間帯以外にブロックするドメイン。1行1ドメイン、# 以降はコメント
# curfeed add youtube.com のように登録します（curfeed remove で削除）。www. の有無は別のドメインとして扱います
EOF
  fi
}

# 「HHMM-HHMM」が許可時間帯として正しければ成功する。開始 24:00 と、開始と終了が同じものは不可
valid_window() {
  case $1 in
    [0-2][0-9][0-5][0-9]-[0-2][0-9][0-5][0-9]) ;;
    *) return 1 ;;
  esac
  _s=$(to_minutes "${1%-*}") && _e=$(to_minutes "${1#*-}") || return 1
  [ "$_s" -lt 1440 ] && [ "$_s" -ne "$_e" ]
}

# 許可時間帯の重なりやつながりをまとめ、開始時刻の順に並べて出す。
# 0:00 をはさんでつながるものは、日付をまたぐ1つの時間帯（例 2300-0100）にして最後に並べる
merge_windows() {
  printf '%s\n' $1 | awk -F- '
    function minutes(t) { return substr(t, 1, 2) * 60 + substr(t, 3, 2) }
    function hhmm(x) { return sprintf("%02d%02d", int(x / 60), x % 60) }
    NF == 2 {
      s = minutes($1)
      e = minutes($2)
      # 日付をまたぐものは、0:00 で2つに分けて扱う
      if (s < e) { n++; S[n] = s; E[n] = e }
      else {
        n++; S[n] = s; E[n] = 1440
        if (e > 0) { n++; S[n] = 0; E[n] = e }
      }
    }
    END {
      for (i = 2; i <= n; i++) {
        s = S[i]; e = E[i]
        for (j = i - 1; j >= 1 && S[j] > s; j--) { S[j + 1] = S[j]; E[j + 1] = E[j] }
        S[j + 1] = s; E[j + 1] = e
      }
      k = 0
      for (i = 1; i <= n; i++) {
        if (k > 0 && S[i] <= ME[k]) { if (E[i] > ME[k]) ME[k] = E[i] }
        else { k++; MS[k] = S[i]; ME[k] = E[i] }
      }
      first = 1; last = k; cross = ""
      if (k >= 2 && MS[1] == 0 && ME[k] == 1440) {
        cross = hhmm(MS[k]) "-" hhmm(ME[1]); first = 2; last = k - 1
      }
      out = ""
      for (i = first; i <= last; i++) out = out (out == "" ? "" : " ") hhmm(MS[i]) "-" hhmm(ME[i])
      if (cross != "") out = out (out == "" ? "" : " ") cross
      print out
    }'
}

# config から許可時間帯を読み、まとめた結果を allow_windows に入れる。
# 失敗したら理由を curfeed_error に入れて失敗する
load_windows() {
  if [ ! -r "$CURFEED_CONFIG" ]; then
    curfeed_error="設定ファイルを読めません: $CURFEED_CONFIG"
    return 1
  fi
  _raw=$(sed -n 's/^ALLOW=//p' "$CURFEED_CONFIG" | tail -n 1)
  allow_windows=""
  for _w in $(printf '%s' "$_raw" | tr ',' ' '); do
    if ! valid_window "$_w"; then
      curfeed_error="許可時間帯が不正です: '$_w'（${CURFEED_CONFIG}）"
      return 1
    fi
    allow_windows="$allow_windows $_w"
  done
  if [ -z "$allow_windows" ]; then
    curfeed_error="許可時間帯が設定されていません（${CURFEED_CONFIG}）"
    return 1
  fi
  allow_windows=$(merge_windows "$allow_windows")
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

# 引数: 現在（HHMM） 許可時間帯。どれかの許可時間帯に入っていれば成功する
in_any_window() {
  for _w in $2; do
    in_window "$1" "${_w%-*}" "${_w#*-}" && return 0
  done
  return 1
}

# 引数: まとめ済みの許可時間帯。24 時間（00:00〜24:00）なら成功する
is_full_day() {
  [ "$1" = "0000-2400" ]
}

# 許可時間帯を「12:00〜13:00, 21:00〜22:00」の形で表示する
format_windows() {
  _out=""
  for _w in $1; do
    _out="${_out:+$_out, }$(format_time "${_w%-*}")〜$(format_time "${_w#*-}")"
  done
  echo "$_out"
}

# blocklist のドメインを1行ずつ出す（# 以降と空行は除く）
blocklist_domains() {
  awk '{ sub(/#.*/, ""); if (NF) print $1 }' "$CURFEED_BLOCKLIST"
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
  awk -v b="$CURFEED_BEGIN_MARK" -v e="$CURFEED_END_MARK" '
    $0 == b { inside = 1; next }
    $0 == e { inside = 0; next }
    inside && $1 == "0.0.0.0" { print tolower($2) }
  ' "$CURFEED_HOSTS"
}
