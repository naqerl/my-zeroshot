#!/usr/bin/env python3
"""Append the reply-budget instruction to both software-change graphs.

Why: on 2026-10-27 the acceptance verifier of pi-ui phase 2 wrote past its
output budget and its JSON envelope was truncated mid-object
("EOF while parsing an object at line 1 column 5463"), which failed the run as
review_failed even though the diff was fine. A verifier must be able to finish
its answer, so the fix is to bound the answer rather than raise a cap.

The templates are rendered one-line-per-string JSON; re-serialising them with
json.dump rewrites every line, so this patches the two known instruction tails
textually and stays idempotent on the marker sentence.
"""

import pathlib
import sys

MARK = "Budget the reply:"

VERIFIER = (
    " Budget the reply: it must fit in a single message. Emit only the numbered "
    "verdict lines - no diff, no file contents, no restatement of the task, no "
    "closing summary. Cite file:line instead of quoting code, and never quote "
    "more than three lines in one finding. If more than twelve findings would be "
    "reported, report the twelve that matter most and end with the single line "
    "'MORE SUPPRESSED: <number>'."
)

WORKER = (
    " Budget the reply: it must fit in a single message. Report the change as the "
    "hunks you applied - or the tool calls that applied them - never as whole-file "
    "rewrites and never as a diff you have already committed. Do not paste "
    "unchanged file contents, the repository tree, or logs you only read."
)

VERIFIER_TAIL = "only when the current change introduces it."
WORKER_TAIL = "is a protocol error and costs a retry."

TEMPLATES = (
    "templates/software-change.json",
    "templates/software-change-push.json",
)


def main(paths):
    for path in paths:
        file = pathlib.Path(path)
        text = file.read_text()
        if MARK in text:
            print(f"{file}: already patched")
            continue
        verifiers = text.count(VERIFIER_TAIL)
        workers = text.count(WORKER_TAIL)
        if verifiers != 2 or workers != 1:
            print(
                f"{file}: unexpected shape (verifier tails {verifiers}, worker tails "
                f"{workers}); refusing to guess",
                file=sys.stderr,
            )
            return 1
        text = text.replace(VERIFIER_TAIL, VERIFIER_TAIL + VERIFIER)
        text = text.replace(WORKER_TAIL, WORKER_TAIL + WORKER)
        file.write_text(text)
        print(f"{file}: appended to {verifiers} verifiers and {workers} worker")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or TEMPLATES))
