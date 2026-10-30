#!/usr/bin/env bash
# Verify templates/software-change.json before an image is built from it.
#
# The file is the built-in `software-change` graph, verbatim:
#
#   zeroshot template show software-change > templates/software-change.json
#
# Nothing is appended to it. This script fails if the file does not parse, if the graph
# shape drifted from the built-in template, or if a local instruction append crept back
# in — a broken or locally patched graph must never reach a published image.
#
#   ./scripts/verify-template.sh [path/to/template.json]
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
template=${1:-$here/../templates/software-change.json}

failures=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# qc <description> <jq args...> — pass/fail on a jq -e filter reading the template.
qc() {
  local desc=$1
  shift
  if jq -e "$@" "$template" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  bad "jq is installed"
  echo "verify-template: jq is required" >&2
  exit 1
fi
ok "jq is installed"

if [ -f "$template" ]; then ok "template exists: ${template}"; else
  bad "template exists: ${template}"
  exit 1
fi

if jq empty "$template" >/dev/null 2>&1; then ok "template parses as JSON"; else
  bad "template parses as JSON"
  exit 1
fi

# --- top-level shape -----------------------------------------------------------------------
qc "profile is openengine.graph.full/v1" '.profile == "openengine.graph.full/v1"'
for key in profile initialInput policy root; do
  qc "top-level key: $key" --arg k "$key" 'has($k)'
done
qc "initialInput requires task" '(.initialInput.fields.task.required == true)'

# --- graph shape: must match the built-in template -----------------------------------------
qc "node: seq run"            'any(.. | objects; .kind == "seq" and .name == "run")'
qc "node: loop change_loop"   'any(.. | objects; .kind == "loop" and .name == "change_loop")'
qc "node: seq change_iteration" 'any(.. | objects; .kind == "seq" and .name == "change_iteration")'
qc "node: par parallel_reviews" 'any(.. | objects; .kind == "par" and .name == "parallel_reviews")'
qc "node: succeed done"       'any(.. | objects; .kind == "succeed" and .name == "done")'
for name in worker worker_result reviews review_result deliver delivery_result change_attempts_exhausted; do
  qc "node name present: $name" --arg n "$name" 'any(.. | objects; .name? == $n)'
done

qc "worker: builtin.agent.software-worker@1" \
  'any(.. | objects; .worker? == "builtin.agent.software-worker@1")'
qc "acceptance verifier: builtin.agent.acceptance-verifier@1" \
  'any(.. | objects; .worker? == "builtin.agent.acceptance-verifier@1")'
qc "code verifier: builtin.agent.code-verifier@1" \
  'any(.. | objects; .worker? == "builtin.agent.code-verifier@1")'
qc "delivery worker: builtin.git-delivery.pr@2" \
  'any(.. | objects; .worker? == "builtin.git-delivery.pr@2")'
qc "verifier nodes are named acceptance and code" \
  'any(.. | objects; .kind == "verifier" and .name == "acceptance") and any(.. | objects; .kind == "verifier" and .name == "code")'

qc "change_loop maxIterations is 10" \
  '[.. | objects | select(has("maxIterations")) | .maxIterations] == [10]'

# --- pristineness: no local instruction appends may come back -------------------------------
for banned in \
  'Budget the reply' \
  'Publication is never your concern' \
  'Final message contract' \
  'Structured findings are mandatory' \
  'previous round findings arrive as' \
  'ntfy' \
  'npx -y' \
  'chromium-shot' \
  'PLAYWRIGHT_BROWSERS_PATH'
do
  qc "no local append: ${banned}" --arg b "$banned" \
    '[.. | strings | select(contains($b))] | length == 0'
done

# The built-in verifier instructions are short; a locally grown prompt is a drift signal.
qc "no verifier instruction exceeds 1500 characters" \
  '[.. | objects | select(.kind == "verifier") | (.instructions // "") | length] | all(.[]; . < 1500)'

echo
if [ "$failures" -ne 0 ]; then
  printf 'verify-template: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
echo "verify-template: all checks passed"
