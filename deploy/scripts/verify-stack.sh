#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Containers ==="
docker ps --filter name=cultur --format '  {{.Names}} — {{.Status}}' || echo "  No cultur containers"

echo ""
echo "=== 2. Caddy local (port 8080) ==="
http_port="${CULTUR_HTTP_PORT:-8080}"
domain="${CULTUR_DOMAIN:-cultur.eqnox.com}"
api_domain="${CULTUR_API_DOMAIN:-api.cultur.eqnox.com}"

web_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${domain}" "http://127.0.0.1:${http_port}/" 2>/dev/null || echo 000)"
api_body="$(curl -sS -H "Host: ${api_domain}" "http://127.0.0.1:${http_port}/backend/health" 2>/dev/null || echo FAIL)"
echo "  Web  http://127.0.0.1:${http_port}/ (Host: ${domain}) → HTTP ${web_code}"
echo "  API  → ${api_body}"

echo ""
echo "=== 3. Web files in Caddy container ==="
caddy="$(docker ps --format '{{.Names}}' | grep -E 'cultur.*caddy' | head -1 || true)"
if [[ -n "$caddy" ]]; then
  docker exec "$caddy" ls -la /srv/web/index.html /srv/web/main.dart.js 2>&1 | sed 's/^/  /' || echo "  MISSING — wrong volume or CULTUR_DEPLOY_DIR"
else
  echo "  Caddy container not found"
fi

echo ""
echo "=== 4. Public DNS ==="
for host in "$domain" "$api_domain"; do
  rec="$(dig +short "$host" CNAME 2>/dev/null | head -1)"
  a="$(dig +short "$host" A 2>/dev/null | head -1)"
  if [[ -n "$rec" ]]; then
    echo "  OK $host → CNAME $rec"
  elif [[ -n "$a" ]]; then
    echo "  OK $host → A $a"
  else
    echo "  FAIL $host → no DNS (browser cannot open https://${host})"
  fi
done

echo ""
echo "=== 5. Public HTTPS (if DNS exists) ==="
for host in "$domain" "$api_domain"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 "https://${host}/" 2>/dev/null || echo 000)"
  echo "  https://${host}/ → HTTP ${code}"
done
