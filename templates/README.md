# templates/

## `software-change.json`

The built-in `software-change` graph, **verbatim**:

```bash
zeroshot template show software-change > templates/software-change.json
```

Nothing is appended to it — no instruction patches, no extra review inputs, no local
conventions. Node names, bindings, signals, attempts and budgets are exactly what the
zeroshot binary ships, and `scripts/verify-template.sh` fails the image build if the file
drifts from that or if any local append creeps back in.

Submitting with the built-in template needs no graph file at all:

```bash
zeroshot run --template software-change --push --title "…" --input input.json …
```

The copy in this directory exists so a target image can be built and diffed against a known
graph, not so it can be customised.

### Refreshing it

After a zeroshot upgrade:

```bash
zeroshot template show software-change > templates/software-change.json
./scripts/verify-template.sh
git commit -am "chore(templates): refresh software-change from the binary"
```

The verify script prints one line per check; if the graph gained or lost a node, the shape
checks fail and the list tells you which node changed — update `scripts/verify-template.sh`
in the same commit.

### History

This directory used to carry a locally hardened copy (instruction appends for the worker
envelope, review scope, reply budget, visual evidence, plus a separate push variant). That
copy diverged far enough from the binary's graph to make reviews expensive and to reintroduce
prompt text the environment could not honour. It was rolled back to the built-in template;
the appends and the `software-change-push.json` variant are gone, and `--push` at submission
time selects push delivery.
