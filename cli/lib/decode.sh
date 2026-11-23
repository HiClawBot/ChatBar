# Decode SwiftBar drop paths. MIT License.
# DROPPED_FILES is a comma-separated list of file URLs. Paths may be
# percent-encoded, sometimes twice (%2520). Spaces and non-ASCII must survive.
# Bash 3.2 compatible.

cb_urldecode_once() {
  local data="$1"
  local out="" hex byte
  while [[ -n "$data" ]]; do
    if [[ "$data" == %??* ]]; then
      hex="${data:1:2}"
      if [[ "$hex" =~ ^[0-9A-Fa-f]{2}$ ]]; then
        printf -v byte '%b' "\\x${hex}"
        out="${out}${byte}"
        data="${data:3}"
        continue
      fi
    fi
    out="${out}${data:0:1}"
    data="${data:1}"
  done
  printf '%s' "$out"
}

cb_strip_file_url() {
  local u="$1"
  case "$u" in
    file://localhost/*) u="${u#file://localhost}" ;;
    file://127.0.0.1/*) u="${u#file://127.0.0.1}" ;;
    file:///*) u="${u#file://}" ;;
    file://*)
      local rest="${u#file://}"
      if [[ "$rest" == /* ]]; then
        u="$rest"
      else
        u="/${rest#*/}"
      fi
      ;;
  esac
  printf '%s' "$u"
}

cb_looks_encoded() {
  [[ "$1" == *%[0-9A-Fa-f][0-9A-Fa-f]* || "$1" == file:* ]]
}

# Decode one dropped item. Prefer the first decode that names an existing path
# so a real filename containing "%20" is not decoded too far. When nothing
# exists yet, keep decoding while percent-escapes remain (covers double encoding).
cb_decode_dropped_item() {
  local raw="$1"
  local cur="$raw"
  local i=0
  local best=""
  while [[ "$i" -lt 3 ]]; do
    cur="$(cb_urldecode_once "$cur")"
    cur="$(cb_strip_file_url "$cur")"
    # file://%2Ftmp decodes to //tmp. Prefer the single-slash path when it exists.
    if [[ "$cur" == //* ]]; then
      local alt="/${cur#//}"
      while [[ "$alt" == //* ]]; do
        alt="/${alt#//}"
      done
      if [[ -e "$alt" ]]; then
        cur="$alt"
      fi
    fi
    best="$cur"
    if [[ -e "$cur" ]]; then
      printf '%s' "$cur"
      return 0
    fi
    if ! cb_looks_encoded "$cur"; then
      break
    fi
    i=$((i + 1))
  done
  printf '%s' "$best"
}

# Print NUL-separated decoded paths for a DROPPED_FILES string.
cb_split_dropped() {
  local input="$1"
  local rest item decoded
  input="${input//$'\r'/}"
  if [[ "$input" == *$'\n' ]]; then
    input="${input%$'\n'}"
  fi
  [[ -n "$input" ]] || return 0
  rest="$input"
  while true; do
    item="${rest%%,*}"
    if [[ "$rest" == *,* ]]; then
      rest="${rest#*,}"
    else
      rest=""
    fi
    if [[ -n "$item" ]]; then
      decoded="$(cb_decode_dropped_item "$item")"
      if [[ -n "$decoded" ]]; then
        printf '%s\0' "$decoded"
      fi
    fi
    [[ -n "$rest" ]] || break
  done
}
