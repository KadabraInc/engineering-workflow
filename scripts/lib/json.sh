# json.sh — JSON access without a hard dependency on any single runtime.
# Resolution order: jq -> node -> python3. If none exists, JSON_RUNTIME stays
# empty and callers must fail OPEN (a bricked editor is worse than a soft gate);
# common.sh surfaces the condition loudly at session start.
#
# All functions read the JSON document from a file (never stdin) so callers can
# reuse one payload file across many queries. Paths are jq-style dotted paths
# limited to object keys (e.g. .tool_input.file_path) — no array indexing,
# which keeps the node/python fallbacks trivial and identical in behavior.

JSON_RUNTIME=""
if command -v jq >/dev/null 2>&1; then
  JSON_RUNTIME="jq"
elif command -v node >/dev/null 2>&1; then
  JSON_RUNTIME="node"
elif command -v python3 >/dev/null 2>&1; then
  JSON_RUNTIME="python3"
fi

# json_get <file> <dotted.path> [default]
# Prints the value at path as a raw string ("" for null/missing unless a
# default is given). Objects/arrays print as compact JSON.
json_get() {
  local file="$1" path="$2" default="${3-}"
  local out=""
  [ -f "$file" ] || { printf '%s' "$default"; return 0; }
  case "$JSON_RUNTIME" in
    jq)
      # NB: never use '// empty' here — jq's alternative operator treats a
      # legitimate boolean false as missing (real bug caught by the suite).
      out=$(jq -r "${path} | if . == null then empty else (if type == \"object\" or type == \"array\" then tojson else tostring end) end" "$file" 2>/dev/null) || out=""
      ;;
    node)
      out=$(node -e '
        const fs = require("fs");
        try {
          let v = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          for (const k of process.argv[2].split(".").filter(Boolean)) {
            if (v === null || typeof v !== "object") { v = undefined; break; }
            v = v[k];
          }
          if (v === undefined || v === null) process.exit(0);
          process.stdout.write(typeof v === "object" ? JSON.stringify(v) : String(v));
        } catch (e) { process.exit(0); }
      ' "$file" "$path" 2>/dev/null) || out=""
      ;;
    python3)
      out=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        v = json.load(f)
    for k in [p for p in sys.argv[2].split(".") if p]:
        if not isinstance(v, dict):
            v = None
            break
        v = v.get(k)
    if v is None:
        sys.exit(0)
    sys.stdout.write(json.dumps(v) if isinstance(v, (dict, list)) else str(v).lower() if isinstance(v, bool) else str(v))
except Exception:
    sys.exit(0)
' "$file" "$path" 2>/dev/null) || out=""
      ;;
    *)
      out=""
      ;;
  esac
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$default"; fi
}

# json_get_list <file> <dotted.path>
# Prints array-of-strings elements one per line (empty output for missing).
json_get_list() {
  local file="$1" path="$2"
  [ -f "$file" ] || return 0
  case "$JSON_RUNTIME" in
    jq)
      jq -r "(${path}) // [] | .[]" "$file" 2>/dev/null || true
      ;;
    node)
      node -e '
        const fs = require("fs");
        try {
          let v = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          for (const k of process.argv[2].split(".").filter(Boolean)) {
            if (v === null || typeof v !== "object") { v = undefined; break; }
            v = v[k];
          }
          if (Array.isArray(v)) for (const e of v) console.log(String(e));
        } catch (e) {}
      ' "$file" "$path" 2>/dev/null || true
      ;;
    python3)
      python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        v = json.load(f)
    for k in [p for p in sys.argv[2].split(".") if p]:
        v = v.get(k) if isinstance(v, dict) else None
    if isinstance(v, list):
        for e in v:
            print(e)
except Exception:
    pass
' "$file" "$path" 2>/dev/null || true
      ;;
  esac
}

# json_escape <string> — escape for embedding inside a JSON string literal.
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}
