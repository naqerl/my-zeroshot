#!/usr/bin/env bash
# The image's `pi` launcher.
#
# zeroshot launches pi for contained (hosted) placements with `--no-extensions`, which turns
# off *discovery* of ambient extensions, MCP servers, skills and project-local resources so a
# workspace cannot inject them. Explicit `--extension PATH` arguments are still honored — that
# is exactly how zeroshot injects its own active-memory hook on the same argv. This launcher
# uses that documented escape hatch to load the image's own extensions.
#
# The extensions are prepended so they cannot be mistaken for the prompt, which zeroshot passes
# as a positional argument.
set -euo pipefail

args=()
if [ -r /opt/zeroshot/pi-extensions/list ]; then
  while IFS= read -r extension; do
    [ -n "$extension" ] && args+=(--extension "$extension")
  done </opt/zeroshot/pi-extensions/list
fi

exec /opt/zeroshot/bin/node /opt/zeroshot/harness/bin/pi "${args[@]}" "$@"
