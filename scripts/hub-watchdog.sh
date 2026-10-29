#!/usr/bin/env bash
# Restart a wedged zeroshot hub before systemd's healthy view hides it.
#
# A client that abandons a streaming MCP tool call (hub_watch) can leave the hub's MCP worker
# blocked: POST /mcp then accepts connections but never writes a byte, while the API's other
# routes and the reconcile loop keep working. This watchdog sends a bounded MCP initialize and
# restarts the hub after two consecutive failures. A 401 is a configuration error, not a wedge,
# so it never restarts anything.
set -uo pipefail

config_dir=${ZEROSHOT_HUB_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zeroshot/hub}
token_file=${ZEROSHOT_HUB_TOKEN_FILE:-$config_dir/api-token}
state_file=${ZEROSHOT_HUB_WATCHDOG_STATE:-$config_dir/watchdog-failures}
mcp_url=${ZEROSHOT_HUB_MCP_URL:-}

# Prefer the daemon's published endpoint when its heartbeat is readable; otherwise the default.
if [ -z "$mcp_url" ] && [ -r "$config_dir/daemon.json" ] && command -v jq >/dev/null 2>&1; then
  mcp_url=$(jq -r '.mcp // empty' "$config_dir/daemon.json" 2>/dev/null || true)
fi
mcp_url=${mcp_url:-http://127.0.0.1:7383/mcp}

token=$(cat "$token_file" 2>/dev/null || true)
if [ -z "$token" ]; then
  # Let the request answer 401: a missing token is a configuration error, not a wedge.
  printf 'hub-watchdog: token file %s is missing or empty\n' "$token_file" >&2
fi

mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
failures=0
if [ -r "$state_file" ]; then
  read -r failures < "$state_file" 2>/dev/null || true
fi
case $failures in
  ''|*[!0-9]*) failures=0 ;;
esac

payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"zeroshot-hub-watchdog","version":"1"}}}'
status=$(curl -m 8 -sS -o /dev/null -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data "$payload" "$mcp_url" 2>/dev/null)
rc=$?
status=${status//[[:space:]]/}

# A completed initialize is the only proof that the MCP worker is serving again.
if [ "$rc" -eq 0 ] && [ "${status#2}" != "$status" ]; then
  printf '0\n' > "$state_file" 2>/dev/null || true
  exit 0
fi

# 401 means the token is wrong; restarting cannot fix a configuration error.
if [ "$status" = "401" ]; then
  printf 'hub-watchdog: hub MCP rejected the API token (HTTP 401); check %s; not restarting\n' "$token_file" >&2
  printf '0\n' > "$state_file" 2>/dev/null || true
  exit 1
fi

failures=$((failures + 1))
printf '%s\n' "$failures" > "$state_file" 2>/dev/null || true

if [ "$failures" -lt 2 ]; then
  printf 'hub-watchdog: hub MCP check failed (curl exit %s, HTTP %s); failure %s/2\n' \
    "$rc" "${status:-none}" "$failures" >&2
  exit 1
fi

if systemctl --user restart zeroshot-hub.service; then
  printf '0\n' > "$state_file" 2>/dev/null || true
  printf 'hub-watchdog: hub MCP hung (curl exit %s); restarted zeroshot-hub.service after %s consecutive failures\n' \
    "$rc" "$failures" >&2
  exit 0
fi
# Keep the threshold so the next timer tries the restart again instead of waiting for two more.
printf '%s\n' "$failures" > "$state_file" 2>/dev/null || true
printf 'hub-watchdog: hub MCP hung (curl exit %s) and restarting zeroshot-hub.service failed\n' \
  "$rc" >&2
exit 1
