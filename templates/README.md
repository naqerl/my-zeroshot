# templates/

## `software-change.json`

A copy of the built-in `software-change` graph (`zeroshot template show software-change`)
with **three instruction strings changed and nothing else**. Structure, node names, bindings,
signals, attempts and budgets are identical to the built-in template — `scripts/verify-template.sh`
enforces that.

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

### The three appends

| node | worker | appended text |
| --- | --- | --- |
| `worker` | `builtin.agent.software-worker@1` | final-message contract: exactly `{"response": null}` |
| `acceptance` | `builtin.agent.acceptance-verifier@1` | publication is never the reviewer's concern + `{"response": {…}}` contract |
| `code` | `builtin.agent.code-verifier@1` | same review-scope + envelope text as `acceptance` |

### Regenerating after an upstream change

**This file must be regenerated whenever the built-in template changes** — otherwise it silently
pins an old graph. The procedure:

```bash
zeroshot template show software-change > /tmp/software-change.json
python3 -m json.tool /tmp/software-change.json > templates/software-change.json
```

then re-apply the three appends to the `instructions` strings of the nodes listed above (worker,
acceptance, code) — append only, never reword. Then run:

```bash
./scripts/verify-template.sh
```

Two notes:

- The built-in template's `instructions` may already contain the appends if they were upstreamed;
  append only when the sentence is absent, so a regenerated file never carries duplicates.
  `verify-template.sh` fails on duplicates by counting occurrences.
- `verify-template.sh` uses `jq`. If `jq` is unavailable, re-check the same invariants with
  `python3 -c` — the checks are: parses; top-level keys `profile`, `initialInput`, `policy`,
  `root`; three instruction strings carry the appends; node kinds/names unchanged
  (`seq run`, `loop change_loop`, `par parallel_reviews`; names
  `worker|worker_result|reviews|review_result|deliver|delivery_result`); verifier workers
  unchanged; `maxIterations` still 10.

### Optional stronger check (needs the CLI)

`run --validate-only` materialises a graph without submitting anything, so it proves the CLI
itself accepts the file:

```bash
zeroshot run --graph templates/software-change.json --validate-only \
  --title "template validation" --input input.json --runtime-config runtime.json
# {"valid":true}
```

`--input` must satisfy the graph's `initialInput` (`{"task": "…"}`) and `--runtime-config` must
bind every executable node (`worker`, `acceptance`, `code` as agents, `deliver` as
`git_delivery`). CI does not run this — it only runs `scripts/verify-template.sh`, which needs no
CLI.
