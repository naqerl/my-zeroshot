#!/usr/bin/env bash
# Install the zeroshot hub MCP watchdog as user units. Safe to run repeatedly.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
unit_dir=${ZEROSHOT_SYSTEMD_USER_DIR:-$config_home/systemd/user}
hub_dir=${ZEROSHOT_HUB_DIR:-$config_home/zeroshot/hub}

mkdir -p "$unit_dir" "$hub_dir"
install -m 0755 "$here/hub-watchdog.sh" "$hub_dir/hub-watchdog.sh"
install -m 0644 "$here/../systemd/zeroshot-hub-watchdog.service" \
  "$unit_dir/zeroshot-hub-watchdog.service"
install -m 0644 "$here/../systemd/zeroshot-hub-watchdog.timer" \
  "$unit_dir/zeroshot-hub-watchdog.timer"

systemctl --user daemon-reload
systemctl --user enable --now zeroshot-hub-watchdog.timer
