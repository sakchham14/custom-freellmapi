#!/usr/bin/env bash
# Configure nginx: render the config template, optionally enable HTTP Basic
# Auth, then (re)start the stack.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

TEMPLATE="$REPO_ROOT/nginx/nginx.conf.template"
CONF="$REPO_ROOT/nginx/nginx.conf"
HTPASSWD="$REPO_ROOT/nginx/.htpasswd"

mkdir -p "$REPO_ROOT/nginx"

if [ "${ENABLE_NGINX_AUTH:-0}" = "1" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    err "openssl is required for nginx basic auth but was not found"
    exit 1
  fi
  auth_user="${NGINX_AUTH_USER:-freellmapi}"
  auth_pass="${NGINX_AUTH_PASS:-$(openssl rand -base64 12)}"
  openssl passwd -6 -salt "freellmapi" "$auth_pass" > "$HTPASSWD"
  chmod 600 "$HTPASSWD"
  AUTH_BLOCK=$(printf '            auth_basic "Freellmapi";\n            auth_basic_user_file /etc/nginx/.htpasswd;')
  export NGINX_HTPASSWD="$HTPASSWD"
  ok "nginx basic auth enabled (user: $auth_user)"
  warn "password: $auth_pass"
  warn "Save it somewhere safe — it is not stored anywhere else."
else
  rm -f "$HTPASSWD"
  AUTH_BLOCK="            auth_basic off;"
  export NGINX_HTPASSWD="/dev/null"
  ok "nginx basic auth disabled"
fi

# Render the final nginx.conf from the template.
sed "s|^@AUTH_BLOCK@|$AUTH_BLOCK|" "$TEMPLATE" > "$CONF"

log "Restarting stack with nginx ..."
compose down >/dev/null 2>&1 || true
compose up -d --wait

if wait_http "http://127.0.0.1:80/healthz"; then
  ok "nginx is up at http://127.0.0.1:80"
else
  err "nginx did not come up in time"
  exit 1
fi