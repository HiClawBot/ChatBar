# Planner contributions are patches, never commits on main.
# MIT License. See docs/SAFETY.md.

cb_main_commit() {
  local repo="$1"
  if git -C "$repo" rev-parse --verify --quiet main >/dev/null 2>&1; then
    git -C "$repo" rev-parse main
  elif git -C "$repo" rev-parse --verify --quiet master >/dev/null 2>&1; then
    git -C "$repo" rev-parse master
  elif git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    git -C "$repo" rev-parse HEAD
  else
    printf 'none'
  fi
}

cb_safe_repo_rel() {
  local p="$1"
  p="$(cb_trim "$p")"
  p="${p#./}"
  p="${p#\"}"
  p="${p%\"}"
  case "$p" in
    ""|/*|../*|*/../*|*/..|..|*\\*) return 1 ;;
  esac
  local rest="$p" seg
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    rest="${rest#*/}"
    [[ "$rest" == "$seg" ]] && rest=""
    [[ "$seg" == ".." || -z "$seg" ]] && return 1
  done
  printf '%s' "$p"
}

cb_patch_record() {
  local rel="$1"
  local format="$2"
  if [[ "${CB_PATCH_FIRST:-1}" == 1 ]]; then
    CB_PATCH_FIRST=0
  else
    CB_PATCHES_JSON="${CB_PATCHES_JSON},"
  fi
  CB_PATCH_COUNT=$((CB_PATCH_COUNT + 1))
  CB_PATCHES_JSON="${CB_PATCHES_JSON}{\"path\":\"$(cb_json_escape "$rel")\",\"format\":\"${format}\",\"type\":\"code_patch\"}"
}

cb_write_patch_file() {
  local dir="$1"
  local name="$2"
  local body="$3"
  local handoff="$4"
  [[ -n "$(cb_trim "$body")" ]] || return 0
  mkdir -p "$dir"
  local dest="${dir}/${name}"
  local n=2
  while [[ -e "$dest" ]]; do
    dest="${dir}/${n}-${name}"
    n=$((n + 1))
  done
  printf '%s' "$body" | cb_atomic_write "$dest"
  cb_patch_record "$(cb_rel_under "$handoff" "$dest")" "unified_diff"
}

cb_write_full_file() {
  local files_root="$1"
  local rel="$2"
  local body="$3"
  local handoff="$4"
  local safe
  safe="$(cb_safe_repo_rel "$rel")" || {
    cb_warn "rejected unsafe path in planner reply: ${rel}"
    return 0
  }
  local dest="${files_root}/${safe}"
  mkdir -p "$(dirname "$dest")"
  # Keep the write inside patches/files even if the path is tricky.
  case "$dest" in
    "$files_root"/*) ;;
    *) cb_warn "rejected path: ${rel}"; return 0 ;;
  esac
  printf '%s' "$body" | cb_atomic_write "$dest"
  cb_patch_record "$(cb_rel_under "$handoff" "$dest")" "full_file"
}

cb_extract_fences() {
  local src="$1"
  local patch_dir="$2"
  local files_root="$3"
  local handoff="$4"
  local base="$5"
  local line info path pending="" in_fence=0 kind="" fence_path="" buf="" n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_fence" -eq 0 ]]; then
      case "$line" in
        '```diff'|'```diff '*|'```patch'|'```patch '*)
          in_fence=1
          kind="diff"
          buf=""
          continue
          ;;
        '```'*)
          info="${line#\`\`\`}"
          path=""
          case "$info" in
            path:*|file:*) path="${info#*:}" ;;
          esac
          path="$(cb_trim "$path")"
          if [[ -z "$path" && -n "$pending" ]]; then
            path="$pending"
          fi
          pending=""
          if [[ -n "$path" ]]; then
            in_fence=1
            kind="file"
            fence_path="$path"
            buf=""
          fi
          continue
          ;;
        File:*|Path:*|file:*|path:*)
          pending="$(cb_trim "${line#*:}")"
          continue
          ;;
        '### '*|'## '*)
          info="${line#\#\#\# }"
          info="${info#\#\# }"
          info="$(cb_trim "$info")"
          if [[ "$info" == */* || "$info" == *.* ]]; then
            pending="$info"
          fi
          continue
          ;;
      esac
    else
      if [[ "$line" == '```' ]]; then
        if [[ "$kind" == "diff" ]]; then
          n=$((n + 1))
          cb_write_patch_file "$patch_dir" "$(printf '%02d-%s.patch' "$n" "$base")" "$buf" "$handoff"
        elif [[ "$kind" == "file" ]]; then
          cb_write_full_file "$files_root" "$fence_path" "$buf" "$handoff"
        fi
        in_fence=0
        kind=""
        buf=""
        fence_path=""
        continue
      fi
      buf="${buf}${line}"$'\n'
    fi
  done < "$src"
}

cb_collect_patches() {
  local handoff="$1"
  local inbox patch_dir files_root
  inbox="$(cb_dir "$handoff" inbox)"
  patch_dir="${inbox}/patches"
  files_root="${patch_dir}/files"
  rm -rf "$patch_dir"
  mkdir -p "$patch_dir"
  CB_PATCH_COUNT=0
  CB_PATCH_FIRST=1
  CB_PATCHES_JSON="["
  CB_REPLY_TYPE="reply"
  local tsv="${inbox}/.files.tsv"
  [[ -f "$tsv" ]] || {
    CB_PATCHES_JSON="[]"
    rmdir "$patch_dir" 2>/dev/null || true
    return 0
  }
  local path original bytes from_zip zip_name abs base lower
  while IFS="$(printf '\t')" read -r path original bytes from_zip zip_name; do
    [[ -n "$path" ]] || continue
    abs="${handoff}/${path}"
    [[ -f "$abs" ]] || continue
    base="$(basename "$original")"
    base="${base// /-}"
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == *.patch || "$lower" == *.diff ]] || head -n 20 "$abs" | grep -q '^diff --git '; then
      mkdir -p "$patch_dir"
      local dest="${patch_dir}/${base}"
      [[ "$dest" == *.patch || "$dest" == *.diff ]] || dest="${dest}.patch"
      local n=2
      while [[ -e "$dest" ]]; do
        dest="${patch_dir}/${n}-${base}"
        n=$((n + 1))
      done
      cp "$abs" "$dest"
      cb_patch_record "$(cb_rel_under "$handoff" "$dest")" "unified_diff"
      continue
    fi
    case "$lower" in
      *.md|*.txt|*.markdown)
        cb_extract_fences "$abs" "$patch_dir" "$files_root" "$handoff" "$base"
        ;;
    esac
  done < "$tsv"
  if [[ "$CB_PATCH_COUNT" -eq 0 ]]; then
    CB_PATCHES_JSON="[]"
    CB_REPLY_TYPE="reply"
    rm -rf "$patch_dir"
  else
    CB_PATCHES_JSON="${CB_PATCHES_JSON}]"
    CB_REPLY_TYPE="code_patch"
  fi
}

cb_find_new_json() {
  local handoff="$1"
  local inbox_json
  inbox_json="$(cb_dir "$handoff" inbox)/NEW.json"
  if [[ -f "$inbox_json" ]]; then
    printf '%s' "$inbox_json"
    return 0
  fi
  if [[ -f "${handoff}/latest-round.txt" ]]; then
    local rel archived
    rel="$(tr -d '\r\n' < "${handoff}/latest-round.txt")"
    archived="${handoff}/${rel}/inbox/NEW.json"
    if [[ -f "$archived" ]]; then
      printf '%s' "$archived"
      return 0
    fi
  fi
  return 1
}

cb_json_line_value() {
  local file="$1"
  local key="$2"
  local line
  line="$(grep -E "\"${key}\"" "$file" | head -n 1 || true)"
  [[ -n "$line" ]] || return 1
  line="${line#*:}"
  line="$(cb_trim "$line")"
  line="${line%,}"
  line="$(cb_unquote "$line")"
  printf '%s' "$line"
}

cb_cmd_apply() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  cb_resolve_project_arg "$name"
  git -C "$CB_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || cb_die "not a git repo: ${CB_REPO}"
  local manifest
  manifest="$(cb_find_new_json "$CB_HANDOFF")" || cb_die "no NEW.json. Ingest a planner reply first."
  local reply_type round base
  reply_type="$(cb_json_line_value "$manifest" "type" || true)"
  round="$(cb_json_line_value "$manifest" "round" || echo 1)"
  round="$(printf '%s' "$round" | tr -cd '0-9')"
  [[ -n "$round" ]] || round=1
  base="$(cb_json_line_value "$manifest" "base_commit" || true)"
  if [[ "$reply_type" != "code_patch" ]]; then
    cb_die "latest reply is not a code_patch (type=${reply_type:-unknown})"
  fi
  local patch_root
  patch_root="$(dirname "$manifest")/patches"
  [[ -d "$patch_root" ]] || cb_die "no inbox/patches next to ${manifest}"

  local main_ref="" main_before=""
  if git -C "$CB_REPO" rev-parse --verify --quiet main >/dev/null 2>&1; then
    main_ref="main"
  elif git -C "$CB_REPO" rev-parse --verify --quiet master >/dev/null 2>&1; then
    main_ref="master"
  fi
  if [[ -n "$main_ref" ]]; then
    main_before="$(git -C "$CB_REPO" rev-parse "$main_ref")"
  fi
  if [[ -n "$(git -C "$CB_REPO" status --porcelain)" ]]; then
    cb_die "working tree is dirty. chatbar apply will not stash or force."
  fi

  local start="HEAD"
  if [[ -n "$base" && "$base" != "none" ]]; then
    git -C "$CB_REPO" cat-file -e "${base}^{commit}" 2>/dev/null || cb_die "base commit not in this repo: ${base}"
    start="$base"
  fi
  local branch
  branch="chatbar/$(cb_round_label "$round")"
  if git -C "$CB_REPO" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "$CB_REPO" checkout "$branch"
  else
    git -C "$CB_REPO" checkout -b "$branch" "$start"
  fi

  local failed=0
  local patch
  shopt -s nullglob
  local -a patches
  patches=("$patch_root"/*.patch "$patch_root"/*/*.patch)
  shopt -u nullglob
  local applied=0
  if [[ "${#patches[@]}" -gt 0 ]]; then
    for patch in "${patches[@]}"; do
      [[ -f "$patch" ]] || continue
      local err
      err="$(mktemp)"
      if ! git -C "$CB_REPO" apply --3way -- "$patch" >"$err" 2>&1; then
        cb_warn "conflict applying $(basename "$patch"). Not using --force."
        cat "$err" >&2
        git -C "$CB_REPO" diff --name-only --diff-filter=U >&2 || true
        rm -f "$err"
        failed=1
        cb_record_error "$CB_HANDOFF" "conflict applying $(basename "$patch"). Not using --force."
        break
      fi
      rm -f "$err"
      applied=$((applied + 1))
    done
  fi
  if [[ "$failed" -eq 0 && -d "${patch_root}/files" ]]; then
    local full rel dest
    while IFS= read -r full; do
      [[ -f "$full" ]] || continue
      rel="${full#"${patch_root}/files/"}"
      if ! cb_safe_repo_rel "$rel" >/dev/null; then
        cb_warn "skip unsafe full file: ${rel}"
        continue
      fi
      dest="${CB_REPO}/${rel}"
      mkdir -p "$(dirname "$dest")"
      cp "$full" "$dest"
      applied=$((applied + 1))
    done < <(find "${patch_root}/files" -type f -print)
  fi
  if [[ "$applied" -eq 0 && "$failed" -eq 0 ]]; then
    cb_die "no patch or full file to apply"
  fi
  if [[ -n "$main_ref" ]]; then
    local main_after
    main_after="$(git -C "$CB_REPO" rev-parse "$main_ref")"
    if [[ "$main_before" != "$main_after" ]]; then
      cb_die "refusing to move ${main_ref}"
    fi
  fi
  if [[ "$failed" -ne 0 ]]; then
    cb_warn "apply stopped on conflict. ${main_ref:-main} was not moved. Resolve by hand or ask the planner for a new diff."
    cb_record_error "$CB_HANDOFF" "apply stopped on conflict. Not using --force."
    return 1
  fi

  local test_status="not-configured"
  if [[ -n "${CB_TEST_COMMAND:-}" ]]; then
    cb_note "running tests: ${CB_TEST_COMMAND}"
    if (cd "$CB_REPO" && bash -c "$CB_TEST_COMMAND"); then
      test_status="pass"
    else
      test_status="fail"
      cb_warn "tests failed. Not committing. ${main_ref:-main} was not moved."
      cb_record_error "$CB_HANDOFF" "tests failed. Not committing."
      return 1
    fi
  fi

  if [[ -n "$(git -C "$CB_REPO" status --porcelain)" ]]; then
    git -C "$CB_REPO" add -A
    git -C "$CB_REPO" commit -m "chatbar: apply planner patch $(cb_round_label "$round")"
    cb_note "committed on ${branch}"
  else
    cb_note "apply produced no file changes"
  fi
  cb_clear_error "$CB_HANDOFF"
  cb_note "branch=${branch}"
  cb_note "tests=${test_status}"
  if [[ -n "$main_ref" ]]; then
    cb_note "${main_ref} unchanged ${main_before}"
  fi
}
