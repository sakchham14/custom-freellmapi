#!/usr/bin/env bash
# Re-apply FreeLLMAPI gateway compression + response-cache settings.
# Run after any Docker pull/update to restore the token-saving config.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

log "Reapplying FreeLLMAPI gateway config ..."

ENCRYPTION_KEY="$(grep '^ENCRYPTION_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"

$compose_exec node -e "
const s=require('better-sqlite3');
const db=new s('/app/server/data/freeapi.db');
db.prepare(\"INSERT OR REPLACE INTO settings (key,value) VALUES ('compression',?)\").run(JSON.stringify({
  mode:'aggressive', autoTriggerEstTokens:32768, targetTokens:28000, prefixFreeze:true, trustProjectFilters:false,
  engines:{ dedup:{enabled:true,minBlockChars:80,minBlockLines:3}, lite:{enabled:true},
    'read-lifecycle':{enabled:true}, toolfilter:{enabled:true,intensity:'aggressive',maxLinesPerResult:60,maxCharsPerResult:6000,disabledFilters:[]},
    jsoncompact:{enabled:true,minRows:8}, relevance:{enabled:true,maxChars:18000},
    aging:{enabled:true,liveTurns:3,condenseAfterTurns:8}, 'hard-budget':{enabled:true} }
}));
db.prepare(\"INSERT OR REPLACE INTO settings (key,value) VALUES ('response_cache_enabled','1')\").run();
console.log('Gateway config reapplied successfully');
" FREELLMAPI_ENCRYPTION_KEY="$ENCRYPTION_KEY"

ok "Gateway config reapplied"