#!/usr/bin/env bash
# Install FreeLLMAPI (Docker) using the upstream installer, then drop in our
# compose wrapper so nginx + optional auth + optional watchtower come along.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

log "Installing FreeLLMAPI into $FREELLMAPI_DIR ..."

mkdir -p "$FREELLMAPI_DIR"

# Generate .env (encryption key + port) if it doesn't exist yet. The upstream
# installer is idempotent and would preserve an existing one, but generating
# it ourselves means we never depend on the installer's behaviour.
if [ ! -f "$ENV_FILE" ]; then
  log "Generating encryption key + .env ..."
  ENCRYPTION_KEY="$(openssl rand -hex 32)"
  printf 'ENCRYPTION_KEY=%s\nPORT=%s\n' "$ENCRYPTION_KEY" "$FREELLMAPI_PORT" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "encryption key + .env written"
else
  ok ".env already exists; preserving it"
fi

# Our compose file is the one that ships in this repo. Never overwrite it.
if [ ! -f "$COMPOSE_FILE" ]; then
  err "Compose file missing at $COMPOSE_FILE"
  exit 1
fi

# Start only freellmapi now — nginx's config is rendered by setup-nginx.sh
# and its container has nothing to mount until then.
log "Starting freellmapi ..."
compose up -d --wait freellmapi

# Reapply gateway compression + response-cache settings. The upstream image
# resets these on every pull, so we restore them after every (re)start.
if [ -f "$SCRIPT_DIR/reapply-gateway-config.sh" ]; then
  "$SCRIPT_DIR/reapply-gateway-config.sh"
fi

# Verify.
if wait_http "http://127.0.0.1:${FREELLMAPI_PORT}/api/ping"; then
  ok "FreeLLMAPI is up at http://127.0.0.1:${FREELLMAPI_PORT}"
else
  err "FreeLLMAPI did not come up in time"
  exit 1
fi