#!/usr/bin/env bash
set -euo pipefail

# Sync `context.txt` into the n8n workflow node "Agent Context",
# then apply the updated workflow to the local n8n container.
#
# Usage:
#   bash scripts/sync-agent-context.sh
#   CONTEXT_FILE=path/to/context.txt WORKFLOW_FILE=Voice-Lead-Agent.confirm.json bash scripts/sync-agent-context.sh
#   APPLY_N8N=0 bash scripts/sync-agent-context.sh

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_FILE="${CONTEXT_FILE:-$ROOT_DIR/context.txt}"
WORKFLOW_FILE="${WORKFLOW_FILE:-$ROOT_DIR/Voice-Lead-Agent.confirm.json}"
APPLY_N8N="${APPLY_N8N:-1}"

if [[ ! -f "$CONTEXT_FILE" ]]; then
  echo "Missing context file: $CONTEXT_FILE" >&2
  exit 1
fi

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "Missing workflow file: $WORKFLOW_FILE" >&2
  exit 1
fi

python3 - "$CONTEXT_FILE" "$WORKFLOW_FILE" <<'PY'
import json
import sys

context_path = sys.argv[1]
workflow_path = sys.argv[2]

with open(context_path, "r", encoding="utf-8") as f:
  context = f.read().replace("\r\n", "\n").strip()

def escape_for_template_literal(s: str) -> str:
  return (
    s.replace("\\", "\\\\")
     .replace("`", "\\`")
     .replace("${", "\\${")
  )

escaped = escape_for_template_literal(context)
new_function_code = f"const agent_context = `{escaped}`.trim();\n\nreturn [{{ json: {{ ...$json, agent_context }} }}];\n"

workflow_raw = open(workflow_path, "r", encoding="utf-8").read()
workflow = json.loads(workflow_raw)

nodes = workflow.get("nodes")
if not isinstance(nodes, list):
  raise SystemExit("Invalid workflow JSON: missing nodes[]")

target = None
for n in nodes:
  if isinstance(n, dict) and n.get("name") == "Agent Context":
    target = n
    break

if target is None:
  raise SystemExit('Could not find node named "Agent Context"')

params = target.get("parameters") or {}
old_function_code = params.get("functionCode")
if not isinstance(old_function_code, str) or not old_function_code.strip():
  raise SystemExit('Node "Agent Context" has no parameters.functionCode')

old_literal = json.dumps(old_function_code, ensure_ascii=True)
new_literal = json.dumps(new_function_code, ensure_ascii=True)

count = workflow_raw.count(old_literal)
if count != 1:
  raise SystemExit(f"Expected to find exactly 1 functionCode literal to replace, found {count}. Aborting.")

updated = workflow_raw.replace(old_literal, new_literal, 1)
with open(workflow_path, "w", encoding="utf-8") as f:
  f.write(updated)

print(f"Updated {workflow_path} from {context_path}")
PY

if [[ "$APPLY_N8N" == "0" ]]; then
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found; updated workflow file only." >&2
  exit 0
fi

cd "$ROOT_DIR"

WORKFLOW_ID="$(python3 - <<'PY'
import json
wf=json.load(open("Voice-Lead-Agent.confirm.json","r",encoding="utf-8"))
print(wf.get("id",""))
PY
)"

if [[ -z "$WORKFLOW_ID" ]]; then
  echo "Could not read workflow id from Voice-Lead-Agent.confirm.json" >&2
  exit 1
fi

echo "Applying workflow to n8n (id: $WORKFLOW_ID)..."

docker cp "$WORKFLOW_FILE" challenge_n8n:/tmp/Voice-Lead-Agent.confirm.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/Voice-Lead-Agent.confirm.json
docker compose exec -T n8n n8n publish:workflow --id="$WORKFLOW_ID"
docker compose restart n8n

echo "Done."
