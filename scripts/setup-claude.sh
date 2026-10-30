#!/usr/bin/env bash
# Configure Claude Code to route through the nginx proxy.
#
# - Reads the unified API key straight from the FreeLLMAPI settings table
#   (it is stored in plaintext there) — no secrets in this repo, no
#   manual copy-paste, no crypto needed.
# - Writes ~/.claude/settings.json from the template, with:
#     * ANTHROPIC_BASE_URL pointing at the nginx proxy (port 80)
#     * ANTHROPIC_AUTH_TOKEN = the unified key
#     * autoCompact + gateway model discovery enabled
#     * shared-memory MCP server + SessionStart/SessionEnd hooks (optional)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

USE_MEMORY="${USE_MEMORY:-1}"

# --- Resolve the unified API key from the FreeLLMAPI DB -------------------
log "Resolving unified API key from FreeLLMAPI ..."
UNIFIED_KEY="$($compose_exec node -e "
const s=require('better-sqlite3');
const db=new s('/app/server/data/freeapi.db');
const row=db.prepare(\"SELECT value FROM settings WHERE key='unified_api_key'\").get();
if(!row){ console.error('no unified key found'); process.exit(1); }
console.log(row.value);
" 2>&1)"

if [ -z "$UNIFIED_KEY" ]; then
  err "Could not resolve unified API key"
  exit 1
fi
ok "unified API key resolved"

# --- Write Claude Code settings -------------------------------------------
SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"

if [ "$USE_MEMORY" = "1" ]; then
  cp "$REPO_ROOT/templates/settings.json" "$SETTINGS_FILE"
else
  cp "$REPO_ROOT/templates/settings-no-memory.json" "$SETTINGS_FILE"
fi

# Substitute the placeholder with the real key.
sed -i "s/FREELLMAPI_API_KEY_PLACEHOLDER/$UNIFIED_KEY/g" "$SETTINGS_FILE"

# Point the base URL at nginx (port 80) so traffic goes through the proxy.
if ! jq -e --arg url "http://localhost:80/v1" \
     '.env.ANTHROPIC_BASE_URL = $url' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"; then
  err "jq failed to update settings"
  exit 1
fi
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

chmod 600 "$SETTINGS_FILE"
ok "Claude Code settings written to $SETTINGS_FILE"
log "  ANTHROPIC_BASE_URL = http://localhost:80/v1"
log "  shared-memory MCP  = $([ "$USE_MEMORY" = "1" ] && echo enabled || echo disabled)"