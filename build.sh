#!/usr/bin/env bash
# Build the my-zeroshot target image.
#
# The zeroshot source is not vendored here: this script clones it at a pinned ref, overlays the
# operator files (Dockerfile, restic shim, pi launcher), and builds from that directory so the
# upstream Dockerfile's COPY paths keep working unchanged.
#
#   ./build.sh                       # naqerl/zeroshot feat/hub
#   ZEROSHOT_REPO=... ZEROSHOT_REF=... ./build.sh
#   TAG=my-zeroshot:dev ./build.sh
set -euo pipefail

REPO=${ZEROSHOT_REPO:-https://github.com/naqerl/zeroshot.git}
REF=${ZEROSHOT_REF:-feat/hub}
TAG=${TAG:-my-zeroshot:$(git rev-parse --short HEAD 2>/dev/null || echo dev)}
WORK=${WORK:-.build}
PLATFORM=${PLATFORM:-linux/amd64}

here=$(cd "$(dirname "$0")" && pwd)

if [ ! -d "$WORK/.git" ]; then
  mkdir -p "$WORK"
  git clone --filter=blob:none --no-checkout "$REPO" "$WORK"
fi

# Fetch the ref explicitly, then resolve it to a commit before checking out: `git checkout
# --detach <branch>` is ambiguous (and fails outright on older git) when the name matches a
# local branch.
git -C "$WORK" fetch --quiet --tags origin "$REF" 2>/dev/null \
  || git -C "$WORK" fetch --quiet --all --tags
revision=$(git -C "$WORK" rev-parse --verify --quiet "$REF^{commit}" \
  || git -C "$WORK" rev-parse --verify --quiet "origin/$REF^{commit}")
if [ -z "$revision" ]; then
  echo "cannot resolve $REF in $REPO" >&2
  exit 1
fi
git -C "$WORK" checkout --quiet --force --detach "$revision"
git -C "$WORK" submodule update --init --recursive --quiet 2>/dev/null || true

# Operator overlay: kept out of the zeroshot repository on purpose.
mkdir -p "$WORK/docker/pi"
install -m 0644 "$here/docker/zeroshot-target/Dockerfile.target" "$WORK/docker/zeroshot-target/Dockerfile.target"
install -m 0755 "$here/docker/zeroshot-target/restic-shim.sh"  "$WORK/docker/zeroshot-target/restic-shim.sh"
install -m 0755 "$here/docker/pi/resolve-extensions.sh"        "$WORK/docker/pi/resolve-extensions.sh"
install -m 0755 "$here/docker/pi/pi-launcher.sh"               "$WORK/docker/pi/pi-launcher.sh"

docker build \
  --platform "$PLATFORM" \
  --file "$WORK/docker/zeroshot-target/Dockerfile.target" \
  --build-arg ZEROSHOT_VERSION="${ZEROSHOT_VERSION:-$(git -C "$WORK" describe --tags --always)}" \
  --build-arg VCS_REF="$revision" \
  --tag "$TAG" \
  "$WORK"

printf 'built %s from %s@%s\n' "$TAG" "$REPO" "$revision"
