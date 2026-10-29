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
FINDINGS_APPEND='Structured findings are mandatory.'
CLOSED_APPEND='Previous round findings arrive as acceptanceFeedback and codeFeedback'
REPLY_BUDGET='Budget the reply: it must fit in a single message'
VERDICT_BUDGET='Hard reply budget: the entire final message must stay under 1500 characters including the {"response": {...}} wrapper; at most 12 verdict lines; each line at most 120 characters; when the budget is tight drop the file:line evidence rather than the verdict; never repeat the task, never add prose or a summary.'

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
qc "structured-findings append present on both verifiers" --arg f "$FINDINGS_APPEND" \
  '[.. | strings | select(contains($f))] | length == 2'
qc "closed-findings append present on both verifiers" --arg c "$CLOSED_APPEND" \
  '[.. | strings | select(contains($c))] | length == 2'
qc "worker reply-budget append present exactly once" --arg b "$REPLY_BUDGET" \
  '[.. | strings | select(contains($b))] | length == 1'
qc "numeric verdict budget present on both verifiers" --arg b "$VERDICT_BUDGET" \
  '[.. | strings | select(contains($b))] | length == 2'
qc "reviewers no longer use the qualitative reply budget" --arg b "$REPLY_BUDGET" \
  '[.. | objects | select(.kind == "verifier" and (.name == "acceptance" or .name == "code")) | .instructions | select(contains($b))] | length == 0'
qc "both verifiers declare the prior-round feedback fields" \
  '[.. | objects | select(.kind=="verifier" and (.name=="acceptance" or .name=="code")) | .input.fields] | length == 2 and all(.[]; has("acceptanceFeedback") and has("codeFeedback"))'
qc "both verifiers bind the prior-round feedback from state" \
  '[.. | objects | select(.kind=="verifier" and (.name=="acceptance" or .name=="code")) | [.inputBindings[].target[0]]] | length == 2 and all(.[]; index("acceptanceFeedback") != null and index("codeFeedback") != null)'

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
