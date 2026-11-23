# Secret redaction for packs. MIT License.
# Heuristic only: exclude dotenv/key files and blank likely secret values.

cb_line_looks_secret() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" =~ (api[_-]?key|secret|password|passwd|access[_-]?key|auth[_-]?token|token)[[:space:]]*[:=] ]]
}

# Read stdin, write redacted text to stdout. Print redacted line count to $2 if set
# via CB_REDACT_COUNT_FILE, and set CB_REDACT_COUNT.
cb_redact_stream() {
  local count_file="${1:-}"
  awk '
    BEGIN { n = 0; inkey = 0 }
    inkey == 1 {
      n++
      if ($0 ~ /-----END [A-Z ]*-----/) { inkey = 0 }
      print "[REDACTED]"
      next
    }
    $0 ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/ {
      n++
      inkey = 1
      print "[REDACTED]"
      next
    }
    {
      line = $0
      if (line ~ /AKIA[0-9A-Z]{16}/) {
        gsub(/AKIA[0-9A-Z]{16}/, "[REDACTED]", line)
        n++
      }
      low = tolower(line)
      if (low ~ /(^|[^a-z])(api[_-]?key|secret|password|passwd|access[_-]?key|auth[_-]?token|token)[[:space:]]*[:=]/) {
        sub(/[:=][[:space:]]*.*/, "= [REDACTED]", line)
        n++
      }
      print line
    }
    END {
      if (countfile != "") {
        print n > countfile
      }
    }
  ' countfile="$count_file"
}

cb_path_looks_sensitive() {
  local path="$1"
  local base
  base="$(basename "$path")"
  case "$base" in
    .env|.env.*|*.pem|*.key|id_rsa|id_rsa.*|credentials.json|credentials.yml|secrets.json)
      return 0
      ;;
  esac
  case "$path" in
    */.env|*/.env.*|*/secrets/*|*/.secrets/*)
      return 0
      ;;
  esac
  return 1
}
