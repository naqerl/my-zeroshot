# my-zeroshot

A [zeroshot](https://github.com/the-open-engine/zeroshot) **target image** with the `pi` harness and
this operator's pi extensions baked in.

Upstream's `docker/zeroshot-target/Dockerfile` ships `codex`, `claude`, `copilot` and pi. This image
ships **pi only**, at a current version, plus three extensions — and, unlike any image built from
upstream, they actually load inside a hosted run.

## Why a separate repo

Two things make the stock image unusable here:

1. **pi is pinned to whatever upstream last bumped**, and the extensions below need a newer pi API.
2. **Hosted runs disable extension discovery.** zeroshot launches pi for a hosted placement with
   `--no-extensions` (`zeroshot/src/native_v2_pi/command.rs:112-127`), whose point is that a checked-out
   workspace must not be able to inject extensions, MCP servers, skills or system prompts into the
   agent. Dropping a file into `~/.pi/agent/extensions/` therefore does nothing on a target.

The escape hatch the code itself documents
(`zeroshot/src/active_memory/hooks/native.rs:143`: *"Explicit extension paths are honored even with
`--no-extensions`"*) is what this image uses: an explicit `--extension <path>` on the argv. zeroshot
already relies on it for its own active-memory hook, so the mechanism is proven in production, not
hoped for.

`docker/pi/pi-launcher.sh` sits on `/usr/local/bin/pi`, reads the baked list of extension paths and
**prepends** `--extension …` to whatever zeroshot passes. Nothing in zeroshot is patched.

## What is included

| Extension | Why |
| --- | --- |
| [`billion-context`](https://www.npmjs.com/package/billion-context) `0.1.207` | Context management for long agent runs: compression of consumed ranges, `compress`/`decompress`/`search_context`. A long zeroshot worker benefits directly. |
| [`@bytetrue/pi-background-terminal`](https://www.npmjs.com/package/@bytetrue/pi-background-terminal) `0.12.0` | `background_run` + `background_status`/`background_kill`: long builds, test suites and dev servers without blocking the agent turn. |
| [`pi-web-access`](https://www.npmjs.com/package/pi-web-access) `0.44.0` | `web_search`, `fetch_content`, `get_search_content` — documentation and API research without leaving the run. |

pi itself: `1.4.0` (`ARG PI_VERSION`).

## Toolchains in the image

The image carries the compilers a job actually uses, so a run never spends its time installing one
the host could have provided — and so a *Go* repository has the same footing as the Rust one the
upstream image was built for.

| Toolchain | Version | Why |
| --- | --- | --- |
| Rust (`cargo`, `rustc`, `clippy`, `rustfmt`) | upstream image | the repositories zeroshot is developed against |
| `cargo-llvm-cov` 0.6.21 + `llvm-tools-preview` | added | measured Rust coverage; without them a coverage job fails with `error: no such command: llvm-cov` |
| Go | `1.26.1` (`golang:1.26.1-trixie`) | Go repositories such as `barse` (`go.mod` requires 1.26.1) |
| `templ` | `0.3.1020` | `barse` generates its `.templ` files with it; editing a template without regenerating leaves the build compiling yesterday's page |
| `sqlc` | `1.31.1` | `make sqlc` |
| `staticcheck` | `2026.2.1` | `make vet` runs `go vet` *and* `staticcheck` |
| `tailwindcss` (standalone) | `4.1.3` | `barse`'s `output.css` is `//go:embed`ed and *not* in the repo: build without it and the binary serves unstyled pages that still report success |
| Playwright chromium (Node package `1.64.1`, plus Go's `playwright-go` `@latest` at build time) and `chromium`'s shared libraries from apt | Node package pinned, Go browser best effort | `barse`'s e2e suite drives a real browser, and a verification step needs `playwright screenshot` without downloading anything at run time. Both browser revisions are baked under `PLAYWRIGHT_BROWSERS_PATH=/opt/playwright`; the Node package is installed globally so its binary is on `PATH`. The Go step stays non-fatal: an image without that browser still builds and unit-tests Go code. |

The versions are `ARG`s, so a repository that moves can be served without editing the Dockerfile.

## What is deliberately excluded

| Excluded | Reason |
| --- | --- |
| `@realmikekelly/pi-mcp-adapter`, `@realmikekelly/pi-mcp-events`, `naqerl/pi-mcp-events-status` | pi in a zeroshot run uses pi's own MCP implementation; a second adapter would fight it. |
| `-builtin:mcp` in `settings.json` | Same reason. |
| `pi-memory` | The run's home is per-run and thrown away; there is nothing durable to remember into. |
| `pi-btw`, `@narumitw/pi-usage` | Human-facing workflows (side conversations, cost readouts) with no meaning inside a batch run. |
| `naqerl/pi-message-timestamps` | Human-facing transcript decoration. |
| `grammar-coach.ts` | Human-facing writing aid. |
| `herdr-agent-state.ts`, `tmuxrd-session.ts` | Host-specific: they talk to this workstation's herdr/tmux sessions, which do not exist in the container. |

## Build

```sh
./build.sh                              # clones naqerl/zeroshot@feat/hub, tags my-zeroshot:<short-sha>
TAG=my-zeroshot:dev ./build.sh
ZEROSHOT_REPO=https://github.com/the-open-engine/zeroshot.git \
ZEROSHOT_REF=main ./build.sh
```

`build.sh` clones the zeroshot source into `.build/`, overlays the files in this repo (the Dockerfile,
the restic shim, the pi launcher) at the paths upstream's `COPY` instructions expect, and builds from
there. The source is never vendored, and this repo stays readable.

CI builds the same image for `linux/amd64` and pushes it to `ghcr.io/naqerl/my-zeroshot` on every push
to `main` (see `.github/workflows/image.yml`).

## Run a target

```sh
docker run -d --name zs-target \
  -p 127.0.0.1:18081:8080 \
  -v zs-target-data:/var/lib/zeroshot \
  my-zeroshot:latest \
  target serve --listen 0.0.0.0:8080 \
    --public-origin http://127.0.0.1:18081 \
    --storage /var/lib/zeroshot/native-v2
```

`--public-origin` **must** match the port you published, or the hub refuses the member with
`target OECP endpoint is invalid` (`zeroshot/src/native_v2_target/oecp.rs:43`) — the target advertises
`--public-origin` and the hub checks that it resolves to the same authority it dialled.

## The checkpoint shim

`docker/zeroshot-target/restic-shim.sh` wraps restic so that `backup` gets
`--exclude target --exclude node_modules`. Upstream builds
`restic backup . --json --host zeroshot --pack-size 16` with no excludes
(`zeroshot/src/native_v2_checkpoints/restic.rs:144`), so a Rust workspace's 15 GB `target/` is
snapshotted on every checkpoint; on a 74 GB disk that is what turns a run into
`workspace checkpoint is unavailable: restic operation failed`. The shim keeps checkpoints artefact-free
without patching zeroshot.

Note this only helps the *snapshot*: zeroshot still stages a pre-snapshot copy of the workspace
(`native-v2/checkpoints/<sha>/`) which also contains `target/`. Budget disk accordingly.

## Verifying a build

```sh
docker run --rm my-zeroshot:latest pi --version
docker run --rm my-zeroshot:latest sh -c 'cat /opt/zeroshot/pi-extensions/list'
docker run --rm my-zeroshot:latest restic version          # through the shim
docker run --rm my-zeroshot:latest sh -c 'head -3 /usr/local/bin/restic'
```

To confirm the extensions really load under a hosted-run argv, ask for one of their tools with the
contained flags present:

```sh
docker run --rm my-zeroshot:latest pi --no-extensions --no-approve \
  --tools read,bash,edit,write --print 'list your tools' 2>&1 | head
```

`background_run` or `web_search` in that output means the `--extension` arguments won.

## Screenshots and browsers

Node Playwright is pinned at `1.64.1` (`ARG PLAYWRIGHT_VERSION`) with its matching Chromium
(`chromium-1248`, browser `156.0.8078.4`) installed at build time. The Go e2e suite's
`playwright-go` Chromium is installed by the layer above it, at its own revision, in the same
`PLAYWRIGHT_BROWSERS_PATH=/opt/playwright`. Both work without network access and without root:

```sh
playwright screenshot --viewport-size=1280,800 "data:text/html,<h1>ok</h1>" /tmp/pw.png
chromium --headless --no-sandbox --hide-scrollbars --screenshot=/tmp/cr.png "data:text/html,<h1>ok</h1>"
```

When a page needs a server, start it first on a port the repository's tests already use (for
example the port in its Playwright config or test scripts), wait until it listens, then pass that
URL to either command. If a non-root browser launch needs a home directory, set `HOME=/tmp` for
the command. Do not set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`: a run cannot download or install a
browser, so use the versions the image already ships.

## Image tags are not immutable

`workflow_dispatch` builds the *my-zeroshot* commit that triggered it, so re-running the
workflow with a different `zeroshot_ref` input re-pushes the **same** `${GITHUB_SHA::12}` tag
with different content. A pool pinned to that tag silently changes what it runs. When you
need a new binary, push a commit here (even a doc change) so the tag changes with it.
