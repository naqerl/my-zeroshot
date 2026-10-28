#!/usr/bin/env python3
"""Replace the visual-evidence paragraph with a capture cascade that works on a bare box.

The first version told verifiers to run `npx playwright screenshot`, which cannot work in a
repository that does not depend on playwright (pi-ui resolves its e2e stack from `e2e` and
`@e2e-dev/web`). Nothing was uploaded and, because the instruction is best effort, nothing was
reported either. The cascade below tries a system browser first, then a repo-provided script, then
`npx playwright`, and requires the verifier to say which one produced the images.
"""
import json
import sys

FILES = ("templates/software-change.json", "templates/software-change-push.json")
START = "Visual evidence:"
END = "Never capture credentials, tokens, or environment file contents."

NEW = """Visual evidence: when the change touches a rendered surface (files under web/, ui/, client/, src/client/, or any .tsx/.jsx/.css/.html), capture at least two screenshots of the running result and publish each one to ntfy instead of pasting an image into the reply: curl -sS -T /tmp/shot-desktop.png -H 'Filename: shot-desktop.png' -H 'Title: <what it shows>' -H 'Tags: camera:video_camera' https://ntfy.naqerl.com/zeroshot. Use the first capture method that works on this box: (1) a system browser — chromium, chromium-browser or google-chrome with --headless --no-sandbox --hide-scrollbars --window-size=1280,800 --screenshot=/tmp/shot-desktop.png <url>; (2) a screenshot script this repository defines (npm run shot, npm run screenshot, make screenshot, scripts/screenshot.*); (3) npx -y playwright screenshot --viewport-size=1280,800 <url> /tmp/shot-desktop.png. A missing binary is not a reason to skip: try the next method, and state in your reply which method produced the images. Serve the change the way the repository already does it (its own dev or build-then-start command, on a port its tests already use) and stop the server afterwards. Cover desktop and, when the layout is responsive, a mobile width. Best effort for the verdict only: a failed upload is not a finding and must not change a verdict, but you must still say what you attempted. Never capture credentials, tokens, or environment file contents."""


def patch(instructions: str) -> str:
    start = instructions.find(START)
    if start < 0:
        return instructions
    end = instructions.find(END, start)
    if end < 0:
        sys.exit(f"visual-evidence paragraph in {START!r} has no {END!r} terminator")
    tail = instructions[end + len(END):]
    return instructions[:start] + NEW + tail


def walk(node):
    if isinstance(node, dict):
        if "instructions" in node and isinstance(node["instructions"], str):
            node["instructions"] = patch(node["instructions"])
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)


for path in FILES:
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    walk(document)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"patched {path}")
