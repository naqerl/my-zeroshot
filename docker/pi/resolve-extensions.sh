#!/usr/bin/env bash
# Resolve the pi extension entry points of the packages baked into the image.
#
# pi reads a package's `pi.extensions` array (relative to the package root) to know what
# to load, and `--extension` accepts either a file or a directory. Because zeroshot runs
# contained (`--no-extensions`) with explicit `--extension` arguments only, the launcher
# needs absolute paths — this script writes them, one per line.
set -euo pipefail

root=${1:-/opt/zeroshot/pi-extensions/node_modules}
out=${2:-/opt/zeroshot/pi-extensions/list}

: >"$out"
for pkg in "${@:3}"; do
  manifest="$root/$pkg/package.json"
  [ -r "$manifest" ] || { echo "missing package: $pkg" >&2; exit 1; }
  node - "$manifest" "$root/$pkg" >>"$out" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [manifest, dir] = process.argv.slice(2);
const declared = JSON.parse(fs.readFileSync(manifest, 'utf8')).pi?.extensions ?? [];
if (declared.length === 0) {
  console.error(`${manifest}: no pi.extensions`);
  process.exit(1);
}
for (const entry of declared) console.log(path.resolve(dir, entry));
NODE
done

cat "$out"
