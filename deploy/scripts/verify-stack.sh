#!/usr/bin/env bash
set -euo pipefail

web_port="${CULTUR_WEB_PORT:-8081}"
api_port="${CULTUR_API_PORT:-8787}"
host_ip="${CULTUR_HOST_IP:-127.0.0.1}"

echo "=== 1. Containers ==="
docker ps --filter name=cultur --format '  {{.Names}} — {{.Status}}' || echo "  No cultur containers"

echo ""
echo "=== 2. Direct ports (no Caddy) ==="
web_bytes="$(curl -sS "http://${host_ip}:${web_port}/" 2>/dev/null | wc -c || echo 0)"
web_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://${host_ip}:${web_port}/" 2>/dev/null || echo 000)"
js_bytes="$(curl -sS "http://${host_ip}:${web_port}/main.dart.js" 2>/dev/null | wc -c || echo 0)"
api_body="$(curl -sS "http://${host_ip}:${api_port}/backend/health" 2>/dev/null || echo FAIL)"

echo "  Web  http://${host_ip}:${web_port}/ → HTTP ${web_code}, ${web_bytes} bytes"
echo "  JS   http://${host_ip}:${web_port}/main.dart.js → ${js_bytes} bytes (expect millions)"
echo "  API  http://${host_ip}:${api_port}/backend/health → ${api_body}"

echo ""
echo "=== 3. cultur-web container ==="
web_c="$(docker ps --format '{{.Names}}' | grep -E 'cultur.*cultur-web' | head -1 || true)"
if [[ -n "$web_c" ]]; then
  docker exec "$web_c" ls -lh /usr/share/nginx/html/index.html /usr/share/nginx/html/main.dart.js 2>&1 | sed 's/^/  /'
else
  echo "  cultur-web not running"
fi

echo ""
echo "=== 4. Public DNS (optional) ==="
for host in cultur.eqnox.pt api.cultur.eqnox.pt; do
  rec="$(dig +short "$host" CNAME 2>/dev/null | head -1)"
  a="$(dig +short "$host" A 2>/dev/null | head -1)"
  if [[ -n "$rec" ]]; then
    echo "  OK $host → CNAME $rec"
  elif [[ -n "$a" ]]; then
    echo "  OK $host → A $a"
  else
    echo "  ? $host → no DNS"
  fi
done
