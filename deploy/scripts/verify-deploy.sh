#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_ENV="$ROOT/deploy/.env"

if [[ ! -f "$DEPLOY_ENV" ]]; then
  echo "Missing $DEPLOY_ENV" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$DEPLOY_ENV"
set +a

fail=0

echo "== Containers =="
if ! docker ps --format '{{.Names}}\t{{.Status}}' | grep -E '^cultur-' >/dev/null; then
  echo "No cultur-* containers running. Start with: cd deploy && docker compose up -d"
  fail=1
else
  docker ps --format '  {{.Names}} — {{.Status}}' | grep '^  cultur-' || true
fi

echo ""
echo "== API (inside container) =="
if docker ps --format '{{.Names}}' | grep -q '^cultur-cultur-api-1$'; then
  if docker exec cultur-cultur-api-1 python -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/backend/health').read()" \
    >/dev/null 2>&1; then
    echo "  OK — /backend/health"
  else
    echo "  FAIL — API not responding on :8787"
    fail=1
  fi
else
  echo "  SKIP — cultur-cultur-api-1 not running"
  fail=1
fi

echo ""
echo "== DNS (required for HTTPS) =="
for host in "$CULTUR_DOMAIN" "$CULTUR_API_DOMAIN"; do
  ip="$(dig +short "$host" A 2>/dev/null | head -1 || true)"
  if [[ -z "$ip" ]]; then
    echo "  FAIL — no A record for $host (Let's Encrypt will fail until this exists)"
    fail=1
  else
    echo "  OK — $host → $ip"
  fi
done

echo ""
echo "== Caddy (local HTTP, tunnel mode) =="
http_port="${CULTUR_HTTP_PORT:-8080}"
if curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${CULTUR_API_DOMAIN}" "http://127.0.0.1:${http_port}/backend/health" 2>/dev/null | grep -q 200; then
  echo "  OK — http://127.0.0.1:${http_port} with Host ${CULTUR_API_DOMAIN}"
else
  echo "  WARN — Caddy on 127.0.0.1:${http_port} not reachable (use docker-compose.cloudflare.yml)"
fi

echo ""
echo "== HTTPS (public) =="
if [[ "$fail" -eq 0 ]]; then
  for host in "$CULTUR_DOMAIN" "$CULTUR_API_DOMAIN"; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://${host}/" 2>/dev/null || echo 000)"
    if [[ "$code" =~ ^[23] ]]; then
      echo "  OK — https://${host}/ → HTTP $code"
    else
      echo "  FAIL — https://${host}/ → HTTP $code (check: docker logs cultur-caddy-1)"
      fail=1
    fi
  done
else
  echo "  SKIP — fix DNS first, then: cd deploy && docker compose restart caddy"
fi

echo ""
if [[ "$fail" -eq 0 ]]; then
  echo "Deploy checks passed."
else
  echo "Deploy checks failed — see messages above."
  exit 1
fi
