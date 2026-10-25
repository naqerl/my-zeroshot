#!/bin/sh
# LOCAL OPERATOR VARIANT: workspace checkpoints must not snapshot Rust build output.
# zeroshot runs `restic backup . --json ...` with no excludes, so a 15 GB
# workspace/target exhausts the checkpoint budget and the run dies with
# "workspace checkpoint is unavailable: restic operation failed".
# Excluding target/ (and node_modules/) keeps checkpoints small and fast.
if [ "$1" = "backup" ]; then
    exec /usr/local/bin/restic.real "$@" --exclude target --exclude node_modules
fi
exec /usr/local/bin/restic.real "$@"
