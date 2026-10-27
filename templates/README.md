# templates/

## `software-change.json`

A copy of the built-in `software-change` graph (`zeroshot template show software-change`)
with **five instruction appends and one review-input extension, and nothing else**. Structure,
node names, bindings, signals, attempts and budgets are identical to the built-in template —
`scripts/verify-template.sh` enforces that.

Run it instead of `--template software-change`:

```bash
zeroshot run --graph templates/software-change.json --title "…" --input input.json …
```

(equivalently, the MCP `graph` argument takes the same file.)

### Why it exists

Two kinds of waste were observed in real runs of the built-in template:

1. **Review judged publishing, which is not a review concern.** The `code` verifier rejected a
   change because it "had not been pushed to origin/main". Publishing is the delivery node's job —
   the worker has no git credentials, and a local commit in the shared workspace is the correct
   state at review time. The bogus rejection cost a full extra worker pass.
2. **Both verifiers emitted the wrong final-message envelope.** Instead of
   `{"response": {…}}` they returned `{"output":…, "signals":…, "diagnostic":…}`, which the pi
   harness rejects; the harness then asks for a correction, burning a round trip (seen 4× in a
   single run).
3. **Every review round started from nothing.** A verifier saw only `task` and `deliveryFeedback`,
   so round 5 re-derived the requirements from scratch, re-read the whole diff, and happily opened
   findings on code nobody had touched — while dropping what round 3 asked for. That is the single
   largest cost of a long run: ~30–40 minutes per round of reviewer time spent re-deriving.
4. **Rejections were prose.** "needs more tests", "not complete" — the repair worker has to guess,
   and a guess is another round. A rejection that names the criterion and the line can be repaired
   in one pass.
5. **A verifier wrote past its output budget and its envelope never closed.** On 2026-10-27 the
   `acceptance` verifier of a 2-of-4 run produced an answer longer than the model's output budget;
   the JSON was cut mid-object and the whole run failed as `review_failed`
   (`EOF while parsing an object at line 1 column 5463`) although the diff was fine. An unbound
   answer fails silently at the transport layer, so the answer itself must be bounded.

### The appends

| node | worker | appended text |
| --- | --- | --- |
| `worker` | `builtin.agent.software-worker@1` | final-message contract: exactly `{"response": null}` |
| `acceptance` | `builtin.agent.acceptance-verifier@1` | publication is never the reviewer's concern + `{"response": {…}}` contract |
| `code` | `builtin.agent.code-verifier@1` | same review-scope + envelope text as `acceptance` |
| `acceptance`, `code` | both verifiers | structured findings: number the criteria `R1…Rn`, one line per criterion (`R2 FAIL - file:line - what is wrong - what would satisfy it`), and a rejection is exactly the set of FAIL lines |
| `acceptance`, `code` | both verifiers | closed findings: the previous round arrives as `acceptanceFeedback`/`codeFeedback`, every `R#` in it is closed, verify only whether it still fails (`R# STILL FAIL - …`), do not open findings outside the numbering |
| `acceptance`, `code`, `worker` | both verifiers + the worker | reply budget: the answer must fit in one message — verdict lines or applied hunks only, no diff, no file contents, no closing summary; cap the finding list at twelve and end with `MORE SUPPRESSED: <n>` |

### The review-input extension

The last row needs a channel. Both review verifiers therefore declare two **optional** string
inputs and bind them from loop state (which the graph already carries for the repair worker):

```json
"acceptanceFeedback": {"type": {"kind": "string"}, "required": false},
"codeFeedback":       {"type": {"kind": "string"}, "required": false}
```

with matching `inputBindings` of the form
`{"target": ["acceptanceFeedback"], "value": {"source": "state", "path": ["acceptanceFeedback"]}}`.
They are empty on the first round and populated by the previous round's verdict on every later
one, so a repair round is judged against its own closed list instead of a fresh opinion. Nothing
else about the verifier contract changes: same worker, same signals, same attempts.

### Regenerating after an upstream change

**This file must be regenerated whenever the built-in template changes** — otherwise it silently
pins an old graph. The procedure:

```bash
zeroshot template show software-change > /tmp/software-change.json
python3 -m json.tool /tmp/software-change.json > templates/software-change.json
```

then re-apply the worker/reviewer appends to the `instructions` strings of the nodes listed above
(worker, acceptance, code) — append only, never reword — and re-apply the review-loop additions
with the script:

```bash
./scripts/apply-review-loop-additions.py templates/software-change.json \
  templates/software-change-push.json
```

The script is idempotent (it prints `already applied` on a second run), preserves each file's
existing indent so the diff stays reviewable, and fails loudly if it cannot find exactly two
review verifiers. Then run:

```bash
./scripts/verify-template.sh templates/software-change.json
./scripts/verify-template.sh templates/software-change-push.json
```

Two notes:

- The built-in template's `instructions` may already contain the appends if they were upstreamed;
  append only when the sentence is absent, so a regenerated file never carries duplicates.
  `verify-template.sh` fails on duplicates by counting occurrences.
- `verify-template.sh` uses `jq`. If `jq` is unavailable, re-check the same invariants with
  `python3 -c` — the checks are: parses; top-level keys `profile`, `initialInput`, `policy`,
  `root`; five instruction appends present, exactly twice on the two verifiers (worker append
  exactly once); both verifiers declare and bind the prior-round feedback fields; node
  kinds/names unchanged (`seq run`, `loop change_loop`, `par parallel_reviews`; names
  `worker|worker_result|reviews|review_result|deliver|delivery_result`); verifier workers
  unchanged; `maxIterations` still 10.

CI runs both checks (`templates/software-change.json` and `templates/software-change-push.json`)
before the image build, so an append that goes missing fails the build instead of surfacing as a
wasted run.

### Optional stronger check (needs the CLI)

`run --validate-only` materialises a graph without submitting anything, so it proves the CLI
itself accepts the file:

```bash
zeroshot run --graph templates/software-change.json --validate-only \
  --title "template validation" --input input.json --runtime-config runtime.json
# {"valid":true}
```

`--input` must satisfy the graph's `initialInput` (`{"task": "…"}`) and the runtime must cover
every executable node. The shortest working invocation uses one lane for all nodes:

```bash
echo '{"harness": "pi", "provider": "gateway", "size": "medium", "model": "test-model"}' \
  > /tmp/lane.json
zeroshot run --graph templates/software-change.json --validate-only --title validate \
  --input <(echo '{"task": "validate"}') --uniform-runtime-config /tmp/lane.json
```

A per-node `nodes` map is **not** accepted by `--uniform-runtime-config` (it expands one lane
across every node); the map form belongs in `--runtime-config`. CI does not run this check — it
only runs `scripts/verify-template.sh`, which needs no CLI.
