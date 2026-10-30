#!/usr/bin/env bash
# freellmapi-cc-setup — one-command bootstrap of FreeLLMAPI + nginx + Claude Code.
#
# Usage:
#   ./scripts/run.sh                       # interactive: prompts for every option
#   ./scripts/run.sh --quick               # all defaults, no prompts
#   ./scripts/run.sh --quick --no-memory   # skip the shared-memory MCP setup
#   ./scripts/run.sh --enable-nginx-auth   # also enable nginx basic auth
#
# Every option has a documented default; pass --quick to accept all of them.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

# --- Defaults -------------------------------------------------------------
# Memory defaults to LOCAL: Claude Code's built-in auto memory + CLAUDE.md,
# which is machine-local and never leaves this computer. Opt into the
# shared-memory MCP server with --shared-memory.
QUICK=0
USE_SHARED_MEMORY=0
NO_MEMORY=0
ENABLE_NGINX_AUTH=0
SKIP_CLAUDE=0
SKIP_NGINX=0
RUN_WATCHTOWER=0
INSTALL_DEPS=1

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --quick                 Accept all defaults without prompting.
  --shared-memory         Also wire up the shared-memory MCP server
                          (opt-in; local memory is the default).
  --no-memory             Skip memory entirely (no MCP server, no local
                          auto memory settings).
  --enable-nginx-auth     Protect the proxy with HTTP Basic Auth.
  --skip-nginx            Do not start the nginx reverse proxy.
  --skip-claude           Do not write Claude Code settings.
  --watchtower            Also start the Watchtower self-updater.
  --local-only            Skip Claude Code settings AND memory. Use the
                          local gateway instead of Claude login.
  --no-deps               Skip the dependency install step (use if you
                          already have docker, openssl, jq, node, curl).
  --deps-only             Install dependencies and exit. Don't start
                          FreeLLMAPI or write Claude Code settings.
  -h, --help              Show this help.

Defaults: port 3001, bind 127.0.0.1, local memory ON, shared-memory MCP
OFF, nginx auth OFF.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --shared-memory) USE_SHARED_MEMORY=1 ;;
    --no-memory) USE_SHARED_MEMORY=0; NO_MEMORY=1 ;;
    --enable-nginx-auth) ENABLE_NGINX_AUTH=1 ;;
    --skip-nginx) SKIP_NGINX=1 ;;
    --skip-claude) SKIP_CLAUDE=1 ;;
    --local-only) USE_SHARED_MEMORY=0; NO_MEMORY=1; SKIP_CLAUDE=1 ;;
    --no-deps) INSTALL_DEPS=0 ;;
    --deps-only) INSTALL_DEPS=1; SKIP_NGINX=1; SKIP_CLAUDE=1 ;;
    --watchtower) RUN_WATCHTOWER=1 ;;
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
    [yY]) USE_SHARED_MEMORY=0; SKIP_CLAUDE=1 ;;
    *)     SKIP_CLAUDE=0 ;;
  esac
  if [ "$SKIP_CLAUDE" = "0" ]; then
    read -r -p "Use local Claude memory (default) or shared-memory MCP? [L/s]: " _mem
    case "${_mem:-L}" in
      [sS]*) USE_SHARED_MEMORY=1 ;;
      *)     USE_SHARED_MEMORY=0 ;;
    esac
  fi
  read -r -p "Enable nginx basic auth? [y/N]: " _auth
  case "${_auth:-N}" in [yY]*) ENABLE_NGINX_AUTH=1 ;; *) ENABLE_NGINX_AUTH=0 ;; esac
fi

# Re-derive HOST_BIND from the possibly-prompted FREELLMAPI_HOST so the
# interactive bind address actually reaches the compose file.
export HOST_BIND="${FREELLMAPI_HOST:-127.0.0.1}"
export FREELLMAPI_PORT
export USE_SHARED_MEMORY NO_MEMORY ENABLE_NGINX_AUTH

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
if [ "${SKIP_NGINX:-0}" = "1" ] && [ "${SKIP_CLAUDE:-0}" = "1" ] && [ "$INSTALL_DEPS" = "1" ]; then
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

# --- 2. Configure & start nginx -------------------------------------------
if [ "$SKIP_NGINX" = "0" ]; then
  "$SCRIPT_DIR/setup-nginx.sh"
else
  warn "Skipping nginx (proxy will run directly on port $FREELLMAPI_PORT)"
fi

# --- 3. Optional Watchtower ------------------------------------------------
if [ "$RUN_WATCHTOWER" = "1" ]; then
  if [ -z "${WATCHTOWER_TOKEN:-}" ]; then
    warn "WATCHTOWER_TOKEN not set; skipping Watchtower"
  else
    log "Starting Watchtower self-updater ..."
    compose --profile autoupdate up -d watchtower
  fi
fi

# --- 4. Configure Claude Code ---------------------------------------------
if [ "$SKIP_CLAUDE" = "0" ]; then
  "$SCRIPT_DIR/setup-claude.sh"
else
  warn "Skipping Claude Code settings"
fi

# --- Done ------------------------------------------------------------------
ok "All done."
echo
echo "  FreeLLMAPI : http://localhost:${FREELLMAPI_PORT}"
echo "  Proxy      : http://localhost:80"
if [ "$SKIP_CLAUDE" = "1" ]; then
  echo "  Settings   : (not written — local-only mode)"
else
  echo "  Settings   : ~/.claude/settings.json"
fi
echo
if [ "$SKIP_CLAUDE" = "1" ]; then
  echo "Local-only mode: Claude Code is not configured. Point your client at"
  echo "http://localhost:80/v1 with any API key (e.g. 'local') to use the"
  echo "gateway directly, or use ANTHROPIC_BASE_URL=http://localhost:80/v1"
  echo "in your shell before running 'claude'."
else
  echo "Run 'claude' to start a session. To reapply gateway config after an"
  echo "update: ./scripts/reapply-gateway-config.sh"
fi