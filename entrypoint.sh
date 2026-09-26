#!/usr/bin/env bash
# Entrypoint for the headless Orca runtime.
#
# Starts as root only to fix volume ownership, then drops to the unprivileged
# "orca" user before launching the runtime, mirroring Orca's own container
# fixtures (runuser --user orca --preserve-environment).
set -euo pipefail

# Force the volume-backed home. Inheriting root's HOME (/root) would put
# pairing keys, agent credentials, and Orca state outside the mounted volume.
export HOME="/home/orca"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$HOME/.runtime"
export LIBGL_ALWAYS_SOFTWARE=1
export SHELL=/bin/bash
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ORCA_PORT="${ORCA_SERVE_PORT:-6768}"
ORCA_PAIRING="${ORCA_PAIRING_ADDRESS:-wss://localhost:6768}"
ORCA_PROJECT_ROOT="${ORCA_PROJECT_ROOT:-}"
ORCA_LAUNCHER="/opt/orca/root/resources/bin/orca-ide"

mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" /workspace
chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

serve_args=(serve --port "$ORCA_PORT" --pairing-address "$ORCA_PAIRING")
[ -n "$ORCA_PROJECT_ROOT" ] && serve_args+=(--project-root "$ORCA_PROJECT_ROOT")
[ "${ORCA_JSON:-0}" = "1" ] && serve_args+=(--json)

if [ "$(id -u)" = "0" ]; then
  chown -R orca:orca "$HOME" /workspace 2>/dev/null || true
  echo "[orca-entrypoint] launching: orca ${serve_args[*]}"
  exec runuser --user orca --preserve-environment -- "$ORCA_LAUNCHER" "${serve_args[@]}"
fi

echo "[orca-entrypoint] launching as $(id -un): orca ${serve_args[*]}"
exec "$ORCA_LAUNCHER" "${serve_args[@]}"
