# Local tip jar and the scene log. No network. MIT License.

cb_tip_number() {
  local raw="$1" fallback="$2"
  if [[ "$raw" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "$fallback"
  fi
}

cb_tip_minutes() {
  cb_load_global_config
  cb_tip_number "${CB_CFG_TIP_MINUTES:-}" "3"
}

cb_tip_cost() {
  cb_load_global_config
  cb_tip_number "${CB_CFG_TIP_COST:-}" "0"
}

cb_cmd_tip() {
  cb_projects_load
  local actions=0 rounds=0 line file i
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      cb_ensure_layout "$CB_HANDOFF"
      file="$(cb_dir "$CB_HANDOFF" log)/events.jsonl"
      [[ -f "$file" ]] || continue
      while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
          *'"direction":"to_planner"'*)
            actions=$((actions + 1))
            rounds=$((rounds + 1))
            ;;
          *'"direction":"from_planner"'*)
            actions=$((actions + 1))
            ;;
        esac
      done < "$file"
    done
  fi
  local per_min per_cost minutes cost
  per_min="$(cb_tip_minutes)"
  per_cost="$(cb_tip_cost)"
  minutes="$(awk -v a="$actions" -v m="$per_min" 'BEGIN { printf "%.2f", a * m }')"
  cost="$(awk -v r="$rounds" -v c="$per_cost" 'BEGIN { printf "%.2f", r * c }')"
  printf '{'
  printf '"actions":%s,' "$actions"
  printf '"rounds":%s,' "$rounds"
  printf '"minutes_per_action":%s,' "$per_min"
  printf '"cost_per_round":%s,' "$per_cost"
  printf '"minutes_saved":%s,' "$minutes"
  printf '"cost_saved":%s,' "$cost"
  printf '"machine":"%s"' "$(cb_json_escape "$(cb_machine_name)")"
  printf '}\n'
}

cb_cmd_log() {
  cb_projects_load
  local first=1 i file line
  printf '{"events":['
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      file="$(cb_dir "$CB_HANDOFF" log)/events.jsonl"
      [[ -f "$file" ]] || continue
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        if [[ "$first" == 1 ]]; then first=0; else printf ','; fi
        printf '%s' "$line"
      done < "$file"
    done
  fi
  printf ']}\n'
}
