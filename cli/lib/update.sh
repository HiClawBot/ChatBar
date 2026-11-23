# Public, checksummed source releases. Only an explicit update swaps the install.

CB_RELEASES_URL=https://github.com/HiClawBot/ChatBar/releases
CB_CODELOAD_URL=https://codeload.github.com/HiClawBot/ChatBar/tar.gz

cb_version() {
  cb_read_line "$(cb_install_root)/VERSION" 0.1.0
}

cb_update_cache() {
  printf '%s/update-check' "$(cb_home)"
}

cb_update_version_after() {
  local candidate="$1" installed="$2" i
  local -a a b
  local pattern='^[0-9]{1,6}(\.[0-9]{1,6}){2,3}$'
  [[ "$candidate" =~ $pattern && "$installed" =~ $pattern ]] || return 1
  IFS=. read -ra a <<< "$candidate"
  IFS=. read -ra b <<< "$installed"
  for i in 0 1 2 3; do
    if (( 10#${a[$i]:-0} > 10#${b[$i]:-0} )); then return 0; fi
    if (( 10#${a[$i]:-0} < 10#${b[$i]:-0} )); then return 1; fi
  done
  return 1
}

cb_update_available() {
  local day tag
  IFS=' ' read -r day tag <<< "$(cb_read_line "$(cb_update_cache)" '')"
  cb_update_version_after "${tag#v}" "$(cb_version)"
}

cb_update_curl() {
  curl -q --proto '=https' --proto-redir '=https' --location \
    --silent --show-error --connect-timeout 5 --max-time 30 "$@"
}

cb_update_latest_tag() {
  local status tag
  status="$(cb_update_curl --output /dev/null --write-out '%{http_code} %{url_effective}' \
    "${CB_RELEASES_URL}/latest")" || return 1
  case "$status" in
    "200 ${CB_RELEASES_URL}"|"404 "*) return 0 ;;
    "200 ${CB_RELEASES_URL}/tag/v"*) tag="${status##*/}" ;;
    *) return 1 ;;
  esac
  [[ "$tag" =~ ^v[0-9]{1,6}(\.[0-9]{1,6}){2,3}$ ]] || return 1
  printf '%s' "$tag"
}

cb_update_check() (
  local mode="$1" home cache today last old_tag tag
  home="$(cb_home)"
  cache="$(cb_update_cache)"
  today="$(cb_today)"
  IFS=' ' read -r last old_tag <<< "$(cb_read_line "$cache" '')"
  if [[ "$mode" == background && "$last" == "$today" ]]; then exit 0; fi
  cb_lock "$home/.update" || exit 1
  trap 'cb_unlock "$home/.update"' EXIT
  IFS=' ' read -r last old_tag <<< "$(cb_read_line "$cache" '')"
  if [[ "$mode" == background && "$last" == "$today" ]]; then exit 0; fi
  if ! tag="$(cb_update_latest_tag)"; then
    cb_atomic_write_string "$cache" "$today $old_tag"
    cb_die "检查更新失败"
  fi
  cb_atomic_write_string "$cache" "$today $tag"
  if [[ "$mode" == foreground ]]; then
    if cb_update_version_after "${tag#v}" "$(cb_version)"; then
      cb_note "有更新 $tag"
    else
      cb_note "当前已是最新版本"
    fi
  fi
)

cb_update_guard() {
  local root="$1" path canonical changes
  [[ -x "$root/cli/chatbar" && -f "$root/swiftbar/chatbar.1m.sh" ]] ||
    cb_die "无效的 ChatBar 安装目录"
  if [[ -e "$root/.git" ]]; then
    [[ -d "$root/.git" ]] && changes="$(git -C "$root" status --porcelain --untracked-files=all)" &&
      [[ -z "$changes" ]] ||
      cb_die "源码工作区有改动或使用了 Git worktree"
  fi
  cb_projects_load
  for path in "$(cb_home)" "${CB_P_HANDOFF[@]+"${CB_P_HANDOFF[@]}"}" \
    "${CB_P_WORKSPACE[@]+"${CB_P_WORKSPACE[@]}"}" "${CB_P_REPO[@]+"${CB_P_REPO[@]}"}"; do
    [[ -n "$path" ]] || continue
    canonical="$(cb_abs_dir "$path")"
    case "$canonical/" in
      "$root/"*) cb_die "安装目录内有交接目录或项目：$canonical" ;;
    esac
  done
}

cb_update_backup_name() {
  local root="$1" kind="$2" stamp backup seq=0
  stamp="$(cb_now_stamp)"
  while :; do
    printf -v backup '%s.%s-%s-%04d' "$root" "$kind" "$stamp" "$seq"
    [[ -e "$backup" || -L "$backup" ]] || break
    seq=$((seq + 1))
  done
  printf '%s' "$backup"
}

cb_update_previous() {
  local root="$1" candidate latest="" LC_ALL=C
  for candidate in "$root".prev-*; do
    [[ -d "$candidate" && ! -L "$candidate" && -x "$candidate/cli/chatbar" &&
      -f "$candidate/swiftbar/chatbar.1m.sh" ]] || continue
    latest="$candidate"
  done
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

cb_update_install() (
  local mode="$1" root lock stage="" backup="" payload tag manifest digest commit extra
  root="$(cb_install_root)"
  lock="${root}.update-lock"
  cb_lock "$lock" || exit 1
  trap '
    if [[ -n "$backup" && -d "$backup" && ! -e "$root" ]]; then
      mv "$backup" "$root" || cb_warn "恢复安装目录失败：$backup"
    fi
    [[ -z "$stage" ]] || rm -rf "$stage"
    cb_unlock "$lock"
  ' EXIT
  trap 'exit 1' HUP INT TERM
  cb_update_guard "$root"

  if [[ "$mode" == rollback ]]; then
    payload="$(cb_update_previous "$root")" || cb_die "没有可回滚的备份"
    backup="$(cb_update_backup_name "$root" replaced)"
  else
    tag="$(cb_update_latest_tag)" || cb_die "检查更新失败"
    if ! cb_update_version_after "${tag#v}" "$(cb_version)"; then
      cb_note "当前已是最新版本"
      exit 0
    fi
    manifest="$(cb_update_curl --fail "${CB_RELEASES_URL}/download/${tag}/chatbar-source.sha256")" ||
      cb_die "版本 $tag 缺少校验文件"
    IFS=' ' read -r digest commit extra <<< "$manifest"
    [[ "$digest" =~ ^[0-9a-f]{64}$ && "$commit" =~ ^[0-9a-f]{40}$ && -z "$extra" &&
      "$manifest" != *$'\n'* ]] || cb_die "校验文件格式无效"

    stage="$(mktemp -d "${root}.stage.XXXXXXXX")"
    cb_update_curl --fail --output "$stage/source.tar.gz" "${CB_CODELOAD_URL}/${commit}" ||
      cb_die "下载版本 $tag 失败"
    [[ "$(cb_sha256 "$stage/source.tar.gz")" == "$digest" ]] || cb_die "SHA-256 校验失败"
    payload="$stage/source"
    mkdir "$payload"
    tar -xzf "$stage/source.tar.gz" -C "$payload" --strip-components 1 \
      --no-same-owner --no-same-permissions || cb_die "解压版本 $tag 失败"
    [[ -x "$payload/cli/chatbar" && -x "$payload/swiftbar/chatbar.1m.sh" &&
      "$(cb_read_line "$payload/VERSION" '')" == "${tag#v}" ]] || cb_die "更新包内容与版本不符"
    bash -n "$payload/cli/chatbar" && bash -n "$payload/swiftbar/chatbar.1m.sh" ||
      cb_die "更新包脚本有语法错误"
    cb_update_guard "$root"
    backup="$(cb_update_backup_name "$root" prev)"
  fi

  # Leave the source at the same path so CLI and SwiftBar symlinks keep working.
  mv "$root" "$backup" || cb_die "无法备份当前安装"
  [[ ! -e "$root" ]] && mv "$payload" "$root" || cb_die "无法切换安装目录"
  if [[ "$mode" == rollback ]]; then
    cb_note "已回滚，原版本保存在 $backup"
  else
    cb_note "已更新到 ${tag}，旧版保存在 $backup"
  fi
)

cb_cmd_update() {
  case "${1:-}" in
    '') cb_update_install install ;;
    --check) cb_update_check foreground ;;
    --background|--check-if-due) cb_update_check background ;;
    --rollback) cb_update_install rollback ;;
    *) cb_die "usage: chatbar update [--check|--rollback]" ;;
  esac
}
