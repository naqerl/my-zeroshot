#!/usr/bin/env python3
"""Re-apply the review-loop additions to a software-change template copy.

The templates in this directory are copies of the built-in graph plus a small, fixed set of
edits. When the built-in template changes, the copy is regenerated and these edits must be
re-applied; doing that by hand is how one of them silently goes missing. This script applies
them and is idempotent — running it twice changes nothing.

    ./scripts/apply-review-loop-additions.py templates/software-change.json [...]

On each `acceptance` and `code` verifier it:

1. declares two optional string inputs, `acceptanceFeedback` and `codeFeedback`, bound from the
   loop state, so a later round sees the previous round's findings instead of re-deriving them;
2. appends the structured-findings instruction (numbered `R1…Rn`, one line per criterion);
3. appends the closed-findings instruction (a repaired round verifies closed items, not new ones).

The worker envelope and review-scope appends are not handled here: they are part of the
regeneration procedure in README.md, which this script assumes has already run.
"""

import json
import sys

FINDINGS_MARKER = "Structured findings are mandatory."
FINDINGS_TEXT = (
    " Structured findings are mandatory. Begin every review by deriving the acceptance "
    "criteria from the request and numbering them R1, R2, ... in a fixed order, and reuse "
    "exactly that numbering in every later round. Report one line per criterion and nothing "
    "else, in this form: 'R1 PASS - src/module.rs:42 - the evidence that satisfies it' or "
    "'R2 FAIL - src/module.rs:90 - what is wrong - what would satisfy it'. A rejection is "
    "exactly the set of FAIL lines you produced: no prose, no unnumbered complaint, no "
    "renumbering, no criterion that is missing from the numbering."
)

CLOSED_MARKER = "Previous round findings arrive as acceptanceFeedback"
CLOSED_TEXT = (
    " Previous round findings arrive as acceptanceFeedback and codeFeedback; both are empty "
    "on the first round. When either is present this is a repair round, and every R# in them "
    "is closed: do not restate a closed finding as new, do not re-derive it. Verify only "
    "whether the current workspace still fails each closed item, report the ones that do as "
    "'R# STILL FAIL - file:line - what would satisfy it', and say nothing about the ones that "
    "now pass. Open a finding outside the existing numbering only when the current change "
    "introduces it."
)

FEEDBACK_FIELDS = ("acceptanceFeedback", "codeFeedback")
VERIFIERS = ("acceptance", "code")


def state_binding(name):
    return {"target": [name], "value": {"source": "state", "path": [name]}}


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def patch_verifier(node):
    """Apply the three edits to one verifier node; return what changed."""
    changed = []

    fields = node["input"]["fields"]
    for name in FEEDBACK_FIELDS:
        if name not in fields:
            fields[name] = {"type": {"kind": "string"}, "required": False}
            changed.append(f"input.{name}")

    bound = {tuple(binding["target"]) for binding in node.get("inputBindings", [])}
    for name in FEEDBACK_FIELDS:
        if (name,) not in bound:
            node.setdefault("inputBindings", []).append(state_binding(name))
            changed.append(f"binding.{name}")

    instructions = node.get("instructions") or ""
    for marker, text in ((FINDINGS_MARKER, FINDINGS_TEXT), (CLOSED_MARKER, CLOSED_TEXT)):
        if marker not in instructions:
            instructions += text
            changed.append(marker.split()[0].lower())
    node["instructions"] = instructions
    return changed


def indent_of(path):
    """Preserve the copy's existing indent width so regeneration stays reviewable."""
    with open(path, encoding="utf-8") as handle:
        handle.readline()
        second = handle.readline()
    return len(second) - len(second.lstrip(" ")) or 2


def main(paths):
    if not paths:
        raise SystemExit(__doc__)
    failed = False
    for path in paths:
        indent = indent_of(path)
        with open(path, encoding="utf-8") as handle:
            template = json.load(handle)
        verifiers = [
            node
            for node in walk(template.get("root"))
            if node.get("kind") == "verifier"
            and str(node.get("worker", "")).startswith("builtin.agent.")
            and node.get("name") in VERIFIERS
        ]
        if len(verifiers) != len(VERIFIERS):
            print(f"{path}: expected {len(VERIFIERS)} review verifiers, found {len(verifiers)}")
            failed = True
            continue
        for node in verifiers:
            changed = patch_verifier(node)
            state = ", ".join(changed) if changed else "already applied"
            print(f"{path} [{node['name']}]: {state}")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(template, handle, indent=indent, ensure_ascii=False)
            handle.write("\n")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
