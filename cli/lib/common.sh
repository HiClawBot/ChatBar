# ChatBar shared helpers. MIT License.
# SAFETY: never automate a planner chat. See docs/SAFETY.md.
# Bash 3.2 compatible (macOS /bin/bash).

CB_SPEC_VERSION="0"
CB_QUIET="${CB_QUIET:-0}"

cb_die() {
  printf 'chatbar: %s\n' "$*" >&2
  exit 1
}

cb_warn() {
  printf 'chatbar: %s\n' "$*" >&2
}

cb_note() {
  if [[ "$CB_QUIET" != 1 ]]; then
    printf '%s\n' "$*"
  fi
}

cb_home() {
  printf '%s' "${CHATBAR_HOME:-$HOME/handoff}"
}

cb_ensure_home() {
  mkdir -p "$(cb_home)"
}

cb_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

cb_now_stamp() {
  date +"%Y%m%d-%H%M%S"
}

cb_today() {
  date +"%Y-%m-%d"
}

cb_month() {
  date +"%Y-%m"
}

cb_mtime() {
  local target="$1"
  if stat -c %Y "$target" >/dev/null 2>&1; then
    stat -c %Y "$target"
  else
    stat -f %m "$target"
  fi
}

cb_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

cb_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

cb_approx_tokens() {
  local bytes="${1:-0}"
  if [[ -z "$bytes" || "$bytes" -le 0 ]]; then
    printf '0'
  else
    printf '%s' $(( (bytes + 3) / 4 ))
  fi
}

cb_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

cb_json_escape() {
  local s="$1"
  local out="" i c len
  len="${#s}"
  i=0
  while [[ "$i" -lt "$len" ]]; do
    c="${s:i:1}"
    case "$c" in
      $'\\') out="${out}\\\\" ;;
      '"') out="${out}\\\"" ;;
      $'\n') out="${out}\\n" ;;
      $'\r') out="${out}\\r" ;;
      $'\t') out="${out}\\t" ;;
      *) out="${out}${c}" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

cb_yaml_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

cb_unquote() {
  local s
  s="$(cb_trim "$1")"
  local ph=$'\x01'
  if [[ "$s" == \"*\" && ${#s} -ge 2 ]]; then
    s="${s:1:$((${#s} - 2))}"
    s="${s//\\\\/$ph}"
    s="${s//\\\"/\"}"
    s="${s//$ph/\\}"
  elif [[ "$s" == \'*\' && ${#s} -ge 2 ]]; then
    s="${s:1:$((${#s} - 2))}"
  fi
  printf '%s' "$s"
}

# Write stdin to dest via a temp file in the same directory, then rename.
cb_atomic_write() {
  local dest="$1"
  local dir tmp
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  tmp="${dir}/.tmp.$$.${RANDOM}"
  if ! cat > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$dest"
}

cb_atomic_write_string() {
  local dest="$1"
  local data="$2"
  local nl="${3:-1}"
  if [[ "$nl" == 1 ]]; then
    printf '%s\n' "$data" | cb_atomic_write "$dest"
  else
    printf '%s' "$data" | cb_atomic_write "$dest"
  fi
}

cb_abs_dir() {
  local p="$1"
  if [[ "$p" != /* ]]; then
    p="$(pwd)/$p"
  fi
  if [[ -d "$p" ]]; then
    (cd -P "$p" && pwd)
  else
    printf '%s' "$p"
  fi
}

cb_canon_file() {
  local f="$1"
  local dir base
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s' "$(cd -P "$dir" && pwd)" "$base"
  else
    printf '%s' "$f"
  fi
}

cb_b64enc() {
  printf '%s' "$1" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

cb_b64dec() {
  local s="$1"
  local mod pad i
  mod=$(( ${#s} % 4 ))
  pad=0
  if [[ "$mod" -ne 0 ]]; then
    pad=$((4 - mod))
  fi
  i=0
  while [[ "$i" -lt "$pad" ]]; do
    s="${s}="
    i=$((i + 1))
  done
  s="$(printf '%s' "$s" | tr '-_' '+/')"
  if printf '%s' "$s" | base64 -d >/dev/null 2>&1; then
    printf '%s' "$s" | base64 -d
    return 0
  fi
  printf '%s' "$s" | base64 -D
}

cb_decode_cli_arg() {
  local s="$1"
  if [[ "$s" == b64:* ]]; then
    cb_b64dec "${s#b64:}"
  else
    printf '%s' "$s"
  fi
}

# Directory lock. mkdir is atomic on local disks and typical NFS/NAS.
# Re-entrant for the same process. Steal the lock when the holder pid is dead.
cb_lock() {
  local dir="$1"
  local lock="${dir}/.lock"
  local retries="${CB_LOCK_RETRIES:-200}"
  local pause="${CB_LOCK_SLEEP:-0.05}"
  local i=0
  mkdir -p "$dir"
  if [[ -d "$lock" && -f "${lock}/pid" ]]; then
    local holder
    holder="$(cat "${lock}/pid" 2>/dev/null || true)"
    if [[ "$holder" == "$$" ]]; then
      local depth=1
      if [[ -f "${lock}/depth" ]]; then
        depth="$(cat "${lock}/depth" 2>/dev/null || echo 1)"
      fi
      depth=$((depth + 1))
      printf '%s\n' "$depth" > "${lock}/depth"
      return 0
    fi
  fi
  while ! mkdir "$lock" 2>/dev/null; do
    if [[ -f "${lock}/pid" ]]; then
      local pid
      pid="$(cat "${lock}/pid" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$lock"
        continue
      fi
    fi
    i=$((i + 1))
    if [[ "$i" -ge "$retries" ]]; then
      cb_warn "lock timeout: ${lock}"
      return 1
    fi
    sleep "$pause"
  done
  printf '%s\n' "$$" > "${lock}/pid"
  printf '%s\n' "1" > "${lock}/depth"
}

cb_unlock() {
  local dir="$1"
  local lock="${dir}/.lock"
  [[ -d "$lock" ]] || return 0
  local holder
  holder="$(cat "${lock}/pid" 2>/dev/null || true)"
  if [[ -n "$holder" && "$holder" != "$$" ]]; then
    return 0
  fi
  local depth=1
  if [[ -f "${lock}/depth" ]]; then
    depth="$(cat "${lock}/depth" 2>/dev/null || echo 1)"
  fi
  if [[ "$depth" -gt 1 ]]; then
    printf '%s\n' "$((depth - 1))" > "${lock}/depth"
    return 0
  fi
  rm -rf "$lock"
}

cb_default_opener() {
  if [[ -n "${CHATBAR_OPENER:-}" ]]; then
    printf '%s' "$CHATBAR_OPENER"
  else
    printf '%s' '{name}, round {round}: please review the diff and answer the questions at the end'
  fi
}

cb_render_opener() {
  local template="$1"
  local name="$2"
  local round="$3"
  local out="$template"
  out="${out//\{name\}/$name}"
  out="${out//\{project\}/$name}"
  out="${out//\{round\}/$round}"
  printf '%s' "$out"
}

cb_install_root() {
  local lib_dir
  lib_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd -P "${lib_dir}/../.." && pwd
}

cb_sanitize_filename() {
  local base="$1"
  base="${base//$'\n'/_}"
  base="${base//$'\r'/_}"
  base="${base//$'\t'/ }"
  base="${base//\//__}"
  if [[ -z "$base" || "$base" == "." || "$base" == ".." ]]; then
    base="file"
  fi
  printf '%s' "$base"
}

cb_is_normalized_name() {
  [[ "$1" =~ ^r[0-9]+-[0-9]{8}-[0-9]{6}- ]]
}

cb_rel_under() {
  local root="$1"
  local path="$2"
  case "$path" in
    "$root"/*) printf '%s' "${path#"$root"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}
