#!/usr/bin/env bash
# Configure Claude Code to route through the FreeLLMAPI gateway directly.
#
# - Reads the unified API key straight from the FreeLLMAPI settings table
#   (it is stored in plaintext there) — no secrets in this repo, no
#   manual copy-paste, no crypto needed.
# - Writes ~/.claude/settings.json from the template, with:
#     * ANTHROPIC_BASE_URL pointing at the gateway (port 3001)
#     * ANTHROPIC_AUTH_TOKEN = the unified key
#     * autoCompact + gateway model discovery enabled
#     * shared-memory MCP server + SessionStart/SessionEnd hooks (optional)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

# Memory defaults to LOCAL (Claude Code's built-in auto memory + CLAUDE.md).
# The shared-memory MCP server is opt-in via --shared-memory.
USE_SHARED_MEMORY="${USE_SHARED_MEMORY:-0}"
NO_MEMORY="${NO_MEMORY:-0}"

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

if [ "$USE_SHARED_MEMORY" = "1" ]; then
  cp "$REPO_ROOT/templates/settings.json" "$SETTINGS_FILE"
elif [ "$NO_MEMORY" = "1" ]; then
  cp "$REPO_ROOT/templates/settings-no-memory.json" "$SETTINGS_FILE"
else
  cp "$REPO_ROOT/templates/settings-local-memory.json" "$SETTINGS_FILE"
fi

# Substitute the placeholder with the real key. Use | as the delimiter so a key
# containing slashes doesn't break the substitution.
sed_inplace "s|FREELLMAPI_API_KEY_PLACEHOLDER|$UNIFIED_KEY|g" "$SETTINGS_FILE"

# Substitute the memory home + node binary placeholders so the hooks and MCP
# server resolve on the machine actually running the setup (macOS, Linux, WSL).
if [ "$USE_SHARED_MEMORY" = "1" ]; then
  MEM_HOME="$HOME/.claude/mem"
  NODE_BIN="$(command -v node || echo node)"
  sed_inplace "s|FREELLMAPI_MEM_HOME_PLACEHOLDER|$MEM_HOME|g" "$SETTINGS_FILE"
  sed_inplace "s|FREELLMAPI_NODE_BIN_PLACEHOLDER|$NODE_BIN|g" "$SETTINGS_FILE"
fi

# Point the base URL at the gateway directly (port 3001).
if ! jq -e --arg url "http://localhost:${FREELLMAPI_PORT:-3001}/v1" \
     '.env.ANTHROPIC_BASE_URL = $url' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"; then
  err "jq failed to update settings"
  exit 1
fi
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

chmod 600 "$SETTINGS_FILE"
ok "Claude Code settings written to $SETTINGS_FILE"
log "  ANTHROPIC_BASE_URL = http://localhost:${FREELLMAPI_PORT:-3001}/v1"
if [ "$USE_SHARED_MEMORY" = "1" ]; then
  log "  memory            = shared-memory MCP server"
else
  log "  memory            = local (Claude Code auto memory + CLAUDE.md)"
fi