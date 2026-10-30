#!/usr/bin/env bash
# freellmapi-cc-setup — one-command bootstrap of FreeLLMAPI + Claude Code.
#
# FreeLLMAPI serves the API and dashboard directly on port 3001, so this is a
# thin wrapper around the upstream Docker image: it installs deps, starts the
# container, disables the gateway's per-user request history, and writes
# ~/.claude/settings.json so `claude` routes through the proxy.
#
# Memory is local by default (Claude Code auto memory + CLAUDE.md, machine-local,
# never leaves this computer). Opt into the shared-memory MCP server with
# --shared-memory, or disable memory entirely with --no-memory.
#
# Usage:
#   ./scripts/run.sh                       # interactive: prompts for every option
#   ./scripts/run.sh --quick               # all defaults, no prompts
#   ./scripts/run.sh --quick --shared-memory
#   ./scripts/run.sh --quick --no-memory
#   ./scripts/run.sh --quick --local-only
#   ./scripts/run.sh --quick --no-deps
#   ./scripts/run.sh --deps-only
#   ./scripts/run.sh --skip-claude
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

# --- Defaults -------------------------------------------------------------
QUICK=0
USE_SHARED_MEMORY=0
NO_MEMORY=0
SKIP_CLAUDE=0
INSTALL_DEPS=1

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --quick                 Accept all defaults without prompting.
  --shared-memory         Also wire up the shared-memory MCP server
                          (opt-in; local memory is the default).
  --no-memory             Disable memory entirely: no shared-memory MCP
                          server and no local auto memory.
  --skip-claude           Do not write Claude Code settings.
  --local-only            Skip Claude Code settings AND memory. Use the
                          local gateway instead of Claude login.
  --no-deps               Skip the dependency install step (use if you
                          already have docker, openssl, jq, node, curl).
  --deps-only             Install dependencies and exit. Don't start
                          FreeLLMAPI or write Claude Code settings.
  -h, --help              Show this help.

Defaults: port 3001, bind 127.0.0.1, local memory ON, shared-memory MCP
OFF.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --shared-memory) USE_SHARED_MEMORY=1 ;;
    --no-memory) USE_SHARED_MEMORY=0; NO_MEMORY=1 ;;
    --skip-claude) SKIP_CLAUDE=1 ;;
    --local-only) USE_SHARED_MEMORY=0; NO_MEMORY=1; SKIP_CLAUDE=1 ;;
    --no-deps) INSTALL_DEPS=0 ;;
    --deps-only) INSTALL_DEPS=1; SKIP_CLAUDE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# --- Interactive prompts (skipped under --quick) ---------------------------
if [ "$QUICK" = "0" ]; then
  read -r -p "Bind address [127.0.0.1]: " _bind
  FREELLMAPI_HOST="${_bind:-127.0.0.1}"
  read -r -p "Port [3001]: " _port
  FREELLMAPI_PORT="${_port:-3001}"
  read -r -p "Local-only mode (no Claude login, no memory)? [y/N]: " _local
  case "${_local:-N}" in
    [yY]) SKIP_CLAUDE=1 ;;
    *)     SKIP_CLAUDE=0 ;;
  esac
  if [ "$SKIP_CLAUDE" = "0" ]; then
    read -r -p "Use local Claude memory (default) or shared-memory MCP? [L/s]: " _mem
    case "${_mem:-L}" in
      [sS]*) USE_SHARED_MEMORY=1 ;;
      *)     USE_SHARED_MEMORY=0 ;;
    esac
  fi
fi

# Re-derive HOST_BIND from the possibly-prompted FREELLMAPI_HOST so the
# interactive bind address actually reaches the compose file.
export HOST_BIND="${FREELLMAPI_HOST:-127.0.0.1}"
export FREELLMAPI_PORT
export USE_SHARED_MEMORY NO_MEMORY

# --- 0. Install dependencies ----------------------------------------------
# Docker, Docker Compose, OpenSSL, jq, node, curl. The upstream FreeLLMAPI
# Docker guide lists Docker + Compose + OpenSSL as prerequisites; the wrapper
# scripts also call jq/node/curl/git. Idempotent — already-installed packages
# are skipped, so re-running the bootstrap is cheap.
if [ "$INSTALL_DEPS" = "1" ]; then
  "$SCRIPT_DIR/install-deps.sh"
else
  log "Skipping dependency install (--no-deps)"
fi

# --deps-only installs dependencies and stops there.
if [ "$SKIP_CLAUDE" = "1" ] && [ "$INSTALL_DEPS" = "1" ]; then
  ok "Dependencies installed (--deps-only). Nothing else to do."
  exit 0
fi

# --- Preconditions --------------------------------------------------------
require_cmd docker
require_cmd openssl
require_cmd jq
require_cmd node
require_cmd curl

# --- 1. Install FreeLLMAPI ------------------------------------------------
"$SCRIPT_DIR/install-freellmapi.sh"

# --- 2. Configure Claude Code ---------------------------------------------
if [ "$SKIP_CLAUDE" = "0" ]; then
  "$SCRIPT_DIR/setup-claude.sh"
else
  warn "Skipping Claude Code settings"
fi

# --- Done ------------------------------------------------------------------
ok "All done."
echo
echo "  FreeLLMAPI : http://localhost:${FREELLMAPI_PORT}"
echo "  Settings   : $([ "$SKIP_CLAUDE" = "1" ] && echo '(not written — local-only mode)' || echo ~/.claude/settings.json)"
echo
if [ "$SKIP_CLAUDE" = "1" ]; then
  echo "Local-only mode: Claude Code is not configured. Point your client at"
  echo "http://localhost:${FREELLMAPI_PORT}/v1 with any API key (e.g. 'local')"
  echo "to use the gateway directly, or set ANTHROPIC_BASE_URL="
  echo "http://localhost:${FREELLMAPI_PORT}/v1 in your shell before running 'claude'."
else
  echo "Run 'claude' to start a session."
fi