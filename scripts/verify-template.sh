#!/usr/bin/env bash
# Verify templates/software-change.json before an image is built from it.
#
# The file is a copy of the built-in `software-change` graph with three instruction appends
# (worker envelope, acceptance review scope, code review scope). This script fails if the file
# does not parse, if the graph shape drifted from the built-in template, or if any of the three
# appends went missing — a broken graph must never reach a published image.
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

WORKER_APPEND='Final message contract: reply with exactly one JSON object of the form {"response": null}. Any other top-level key (output, signals, payload) is a protocol error and costs a retry.'
REVIEW_APPEND="Publication is never your concern: the delivery node commits, pushes, and opens the pull request. A local commit in the workspace is the correct state for review. Never reject because nothing is pushed, because the remote branch still points at an older revision, or because a pull request does not exist yet; judge only the workspace content, the observable behaviour, and the user's request."
REVIEW_ENVELOPE='{"response": {...}}'

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
for key in profile initialInput policy root; do
  qc "top-level key: $key" --arg k "$key" 'has($k)'
done

# --- the three instruction appends ----------------------------------------------------------
qc "worker envelope append present exactly once" --arg w "$WORKER_APPEND" \
  '[.. | strings | select(contains($w))] | length == 1'
qc "review-scope append present on both verifiers" --arg r "$REVIEW_APPEND" \
  '[.. | strings | select(contains($r))] | length == 2'
qc "reviewer envelope append present on both verifiers" --arg e "$REVIEW_ENVELOPE" \
  '[.. | strings | select(contains($e))] | length == 2'
qc "no reviewer still asks for a top-level output/signals envelope" \
  '[.. | strings | select(contains("Final message contract"))] | length == 3'

# --- graph shape: kinds and names must match the built-in template -------------------------
qc "node: seq run"            'any(.. | objects; .kind == "seq" and .name == "run")'
qc "node: loop change_loop"   'any(.. | objects; .kind == "loop" and .name == "change_loop")'
qc "node: par parallel_reviews" 'any(.. | objects; .kind == "par" and .name == "parallel_reviews")'
for name in worker worker_result reviews review_result deliver delivery_result; do
  qc "node name present: $name" --arg n "$name" 'any(.. | objects; .name? == $n)'
done

qc "verifier worker: builtin.agent.software-worker@1" \
  'any(.. | objects; .worker? == "builtin.agent.software-worker@1")'
qc "verifier worker: builtin.agent.acceptance-verifier@1" \
  'any(.. | objects; .worker? == "builtin.agent.acceptance-verifier@1")'
qc "verifier worker: builtin.agent.code-verifier@1" \
  'any(.. | objects; .worker? == "builtin.agent.code-verifier@1")'
qc "delivery worker: builtin.git-delivery.pr@2 or push@1" \
  'any(.. | objects; (.worker? == "builtin.git-delivery.pr@2") or (.worker? == "builtin.git-delivery.push@1"))'
qc "verifier nodes are named acceptance and code" \
  'any(.. | objects; .kind == "verifier" and .name == "acceptance") and any(.. | objects; .kind == "verifier" and .name == "code")'

# --- budgets --------------------------------------------------------------------------------
qc "change_loop maxIterations is 10" \
  '[.. | objects | select(has("maxIterations")) | .maxIterations] == [10]'

echo
if [ "$failures" -ne 0 ]; then
  printf 'verify-template: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
echo "verify-template: all checks passed"
