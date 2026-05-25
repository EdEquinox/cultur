#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/deploy/.env"

echo "Zone eqnox.com nameservers:"
dig +short eqnox.com NS | sed 's/^/  /'

for host in "$CULTUR_DOMAIN" "$CULTUR_API_DOMAIN"; do
  echo ""
  echo "$host:"
  cname="$(dig +short "$host" CNAME | head -1)"
  a="$(dig +short "$host" A | head -1)"
  if [[ -n "$cname" ]]; then
    echo "  CNAME → $cname"
  elif [[ -n "$a" ]]; then
    echo "  A → $a"
  else
    echo "  FAIL — NXDOMAIN (no DNS record). Browser cannot open this URL."
    echo "        Add a CNAME to your tunnel (*.cfargotunnel.com) in Cloudflare DNS or HostPapa."
  fi
done
