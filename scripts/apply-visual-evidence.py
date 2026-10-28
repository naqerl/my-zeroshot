#!/usr/bin/env python3
"""Make the software-change verifiers publish screenshots of verified UI work.

Why: the operator reviews UI changes from a chat transcript. A verdict line such
as "the header now blurs" is unverifiable, and asking for the artifact after the
fact means another round trip through the hub. A verifier that already ran the
app (the acceptance lane) is the only party holding the rendered result, so it
should push the picture to the operator's topic.

The target is the attachment API of ntfy, not a git artifact: nothing lands in
the repository and nothing is pasted into the reply, which keeps the reply
budget intact.

Patches both graphs textually and stays idempotent on the marker sentence, for
the same reason as apply-output-discipline.py: re-serialising the one-line
JSON rewrites every line of the file.
"""

import pathlib
import sys

MARK = "Visual evidence:"

VISUAL = (
    " Visual evidence: when the change touches a rendered surface (files under "
    "web/, ui/, client/, src/client/, or any .tsx, .jsx, .css or .html file), take "
    "at least two screenshots of the running result with the repository's own "
    "tooling - for example `npx playwright screenshot --viewport-size=1280,800 "
    "<url> /tmp/shot-desktop.png` - and publish each one for the operator instead "
    "of pasting an image into the reply: `curl -sS -T /tmp/shot-desktop.png -H "
    "'Filename: shot-desktop.png' -H 'Title: <what it shows>' -H 'Tags: camera' "
    "https://ntfy.naqerl.com/zeroshot`. Cover the changed surface at desktop width "
    "and again at mobile width when the change is responsive. This is best effort: "
    "a failed upload is not a finding, must not change the verdict, and must be "
    "reported in one line. If the repository has no browser or the app cannot be "
    "started, say so in one line and continue. Never capture credentials, tokens, "
    "or environment file contents."
)

VERIFIER_TAIL = "only when the current change introduces it."
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
        if verifiers != 2:
            print(
                f"{file}: unexpected shape (verifier tails {verifiers}); refusing to guess",
                file=sys.stderr,
            )
            return 1
        text = text.replace(VERIFIER_TAIL, VERIFIER_TAIL + VISUAL)
        file.write_text(text)
        print(f"{file}: appended visual-evidence instruction to {verifiers} verifiers")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or TEMPLATES))
