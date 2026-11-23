# Install updates from public GitHub. Never touches the handoff folder's rounds.
# A check does not install. Install runs only when the user asks.

cb_update_root() {
  if [[ -n "${CHATBAR_INSTALL_ROOT:-}" ]]; then
    (cd -P "$CHATBAR_INSTALL_ROOT" && pwd)
    return 0
  fi
  cb_install_root
}

cb_update_repo() {
  printf '%s' "${CHATBAR_UPDATE_REPO:-HiClawBot/ChatBar}"
}

cb_update_status_path() {
  printf '%s/update-status' "$(cb_home)"
}

cb_update_stamp_path() {
  printf '%s/update-checked' "$(cb_home)"
}

cb_update_flag_path() {
  printf '%s/update-available' "$(cb_home)"
}

cb_update_prev_record() {
  printf '%s/update-prev' "$(cb_home)"
}

cb_update_local_rev() {
  local root="$1"
  if [[ -f "${root}/INSTALL_REV" ]]; then
    tr -d '\r\n' < "${root}/INSTALL_REV"
  else
    printf 'unknown'
  fi
}

cb_update_write_status() {
  local state="$1"
  cb_ensure_home
  printf 'state=%s\nrev=%s\nsha256=%s\nurl=%s\n' \
    "$state" "${CB_UPD_REV:-}" "${CB_UPD_SHA:-}" "${CB_UPD_URL:-}" \
    | cb_atomic_write "$(cb_update_status_path)"
  if [[ "$state" == "available" ]]; then
    printf '%s\n' "${CB_UPD_REV}" | cb_atomic_write "$(cb_update_flag_path)"
  else
    rm -f "$(cb_update_flag_path)"
  fi
}

cb_update_curl() {
  local dest="$1"
  local url="$2"
  command -v curl >/dev/null 2>&1 || cb_die "检查更新需要 curl"
  curl -fsSL --max-time 60 -H "User-Agent: chatbar" -o "$dest" "$url" || cb_die "检查更新失败"
}

cb_update_resolve_live() {
  local repo body tag sha sums
  repo="$(cb_update_repo)"
  body="$(mktemp)"
  command -v curl >/dev/null 2>&1 || cb_die "检查更新需要 curl"
  if curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" -H "User-Agent: chatbar" \
    -o "$body" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null; then
    tag="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$body" | head -n 1)"
  fi
  if [[ -n "${tag:-}" ]]; then
    CB_UPD_REV="$tag"
    CB_UPD_URL="https://codeload.github.com/${repo}/tar.gz/refs/tags/${tag}"
    sums="$(sed -n 's/.*"browser_download_url": *"\([^"]*SHA256SUMS[^"]*\)".*/\1/p' "$body" | head -n 1)"
    if [[ -n "$sums" ]]; then
      local sumfile
      sumfile="$(mktemp)"
      cb_update_curl "$sumfile" "$sums"
      CB_UPD_SHA="$(awk 'NR==1 { print $1 }' "$sumfile")"
      rm -f "$sumfile"
    else
      CB_UPD_SHA=""
    fi
    rm -f "$body"
    return 0
  fi
  rm -f "$body"
  body="$(mktemp)"
  cb_update_curl "$body" "https://api.github.com/repos/${repo}/commits/main"
  sha="$(sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' "$body" | head -n 1)"
  rm -f "$body"
  [[ -n "$sha" ]] || cb_die "检查更新失败"
  CB_UPD_REV="$sha"
  CB_UPD_URL="https://codeload.github.com/${repo}/tar.gz/${sha}"
  CB_UPD_SHA=""
}

cb_update_resolve() {
  CB_UPD_REV=""
  CB_UPD_SHA=""
  CB_UPD_URL=""
  if [[ -n "${CHATBAR_UPDATE_FIXTURE:-}" ]]; then
    CB_UPD_REV="$(tr -d '\r\n' < "${CHATBAR_UPDATE_FIXTURE}/remote-rev")"
    CB_UPD_SHA="$(tr -d '\r\n' < "${CHATBAR_UPDATE_FIXTURE}/remote-sha256")"
    CB_UPD_URL="${CHATBAR_UPDATE_FIXTURE}/chatbar.tar.gz"
    return 0
  fi
  cb_update_resolve_live
}

cb_update_fetch() {
  local dest="$1"
  if [[ -f "$CB_UPD_URL" ]]; then
    cp "$CB_UPD_URL" "$dest"
    return 0
  fi
  cb_update_curl "$dest" "$CB_UPD_URL"
}

cb_update_verify() {
  local file="$1"
  local actual
  actual="$(cb_sha256 "$file")"
  if [[ -n "${CB_UPD_SHA:-}" ]]; then
    if [[ "$actual" != "$CB_UPD_SHA" ]]; then
      cb_die "sha256 不符，已停止安装"
    fi
    return 0
  fi
  local tmp top raw repo ref
  tmp="$(mktemp -d)"
  tar -xzf "$file" -C "$tmp"
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -f "${top}/cli/chatbar" ]] || {
    rm -rf "$tmp"
    cb_die "更新包不完整"
  }
  raw="$(mktemp)"
  repo="$(cb_update_repo)"
  ref="$CB_UPD_REV"
  if ! curl -fsSL --max-time 30 -H "User-Agent: chatbar" \
    -o "$raw" "https://raw.githubusercontent.com/${repo}/${ref}/cli/chatbar"; then
    rm -rf "$tmp" "$raw"
    cb_die "没有 sha256，不安装"
  fi
  if ! cmp -s "${top}/cli/chatbar" "$raw"; then
    rm -rf "$tmp" "$raw"
    cb_die "sha256 不符，已停止安装"
  fi
  CB_UPD_SHA="$actual"
  rm -rf "$tmp" "$raw"
}

cb_update_check() {
  cb_update_resolve
  local root local_rev
  root="$(cb_update_root)"
  local_rev="$(cb_update_local_rev "$root")"
  if [[ "$local_rev" == "$CB_UPD_REV" ]]; then
    cb_update_write_status "current"
    cb_note "已是最新"
    return 0
  fi
  local tar
  tar="$(mktemp)"
  cb_update_fetch "$tar"
  cb_update_verify "$tar"
  rm -f "$tar"
  cb_update_write_status "available"
  cb_note "有更新 ${CB_UPD_REV}"
}

cb_update_check_if_due() {
  local stamp now then interval
  stamp="$(cb_update_stamp_path)"
  interval="${CHATBAR_UPDATE_INTERVAL:-86400}"
  if [[ -f "$stamp" ]]; then
    now="$(date +%s)"
    then="$(tr -d '\r\n' < "$stamp")"
    if [[ "$then" =~ ^[0-9]+$ ]] && [[ $((now - then)) -lt "$interval" ]]; then
      return 0
    fi
  fi
  cb_ensure_home
  date +%s | cb_atomic_write "$stamp"
  cb_update_check || true
}

cb_update_install() {
  cb_update_resolve
  local root local_rev tar tmp top ts prev
  root="$(cb_update_root)"
  local_rev="$(cb_update_local_rev "$root")"
  if [[ "$local_rev" == "$CB_UPD_REV" ]]; then
    cb_update_write_status "current"
    cb_note "已是最新"
    return 0
  fi
  tar="$(mktemp)"
  cb_update_fetch "$tar"
  cb_update_verify "$tar"
  tmp="$(mktemp -d)"
  tar -xzf "$tar" -C "$tmp"
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$top" && -d "$top" ]] || cb_die "更新包不完整"
  ts="$(date +%Y%m%d-%H%M%S)"
  prev="${root}.prev-${ts}"
  cp -a "$root" "$prev"
  find "$root" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "${top}/." "$root/"
  printf '%s\n' "$CB_UPD_REV" | cb_atomic_write "${root}/INSTALL_REV"
  if [[ -f "${root}/cli/chatbar" ]]; then
    chmod +x "${root}/cli/chatbar" || true
  fi
  cb_ensure_home
  printf 'root=%s\nprev=%s\n' "$root" "$prev" | cb_atomic_write "$(cb_update_prev_record)"
  cb_update_write_status "current"
  rm -rf "$tmp" "$tar"
  cb_note "已安装 ${CB_UPD_REV}"
  cb_note "备份 ${prev}"
}

cb_update_rollback() {
  local record root prev ts failed
  record="$(cb_update_prev_record)"
  [[ -f "$record" ]] || cb_die "没有可还原的版本"
  root="$(sed -n 's/^root=//p' "$record" | head -n 1)"
  prev="$(sed -n 's/^prev=//p' "$record" | head -n 1)"
  [[ -n "$root" && -d "$prev" ]] || cb_die "备份不在了"
  ts="$(date +%Y%m%d-%H%M%S)"
  failed="${root}.failed-${ts}"
  mv "$root" "$failed"
  mv "$prev" "$root"
  cb_note "已还原 ${root}"
}

cb_cmd_update() {
  local mode="install"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) mode="check"; shift ;;
      --check-if-due) mode="due"; shift ;;
      --rollback) mode="rollback"; shift ;;
      *) cb_die "unknown flag: $1" ;;
    esac
  done
  case "$mode" in
    check) cb_update_check ;;
    due) cb_update_check_if_due ;;
    rollback) cb_update_rollback ;;
    install) cb_update_install ;;
  esac
}
