#!/usr/bin/env bash
# Shared helpers for freellmapi-cc-setup.
# Sourced by the other scripts; never executed directly.
set -euo pipefail

# --- Paths ---------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FREELLMAPI_DIR="${FREELLMAPI_DIR:-$HOME/freellmapi}"
export FREELLMAPI_PORT="${FREELLMAPI_PORT:-3001}"
export HOST_BIND="${HOST_BIND:-${FREELLMAPI_HOST:-127.0.0.1}}"
export COMPOSE_DIR="$REPO_ROOT/compose"
export COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
export ENV_FILE="$FREELLMAPI_DIR/.env"
# docker compose resolves env_file paths relative to the compose file's
# directory, so pass the absolute path explicitly via the host environment.
export FREELLMAPI_ENV_FILE="$ENV_FILE"

# --- Portable in-place sed -----------------------------------------------
# macOS sed needs an explicit backup suffix; GNU sed treats an empty one as
# "no backup". This helper gives both the same behaviour.
sed_inplace() {
  if [ "$(uname -s)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# --- Logging -------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m  x\033[0m %s\n' "$*" >&2; }

# --- Preconditions -------------------------------------------------------
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command not found: $1"
    exit 1
  fi
}

# --- OS detection --------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      err "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac
}

# --- Wait for a URL to respond -------------------------------------------
wait_http() {
  local url="$1" tries="${2:-60}" i
  for ((i=1; i<=tries; i++)); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# --- Docker compose helpers ----------------------------------------------
# No --project-name: let docker derive it from the directory so repeated runs
# on the same host never collide with an existing stack.
compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

# Resolve the freellmapi container's service name for exec. With no project
# name the service is still called "freellmapi".
compose_exec() {
  docker compose -f "$COMPOSE_FILE" exec -T freellmapi "$@"
}