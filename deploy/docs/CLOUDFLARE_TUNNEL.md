# cultur + Cloudflare Tunnel

With a Cloudflare Tunnel you **do not** open ports 80/443 on the router, and **Caddy must not** request Let's Encrypt certificates (Cloudflare already serves HTTPS to browsers).

## Architecture

```text
Browser ──HTTPS──► Cloudflare ──tunnel──► cloudflared ──HTTP──► Caddy :80 (localhost)
                                                              ├─ cultur.eqnox.com  → Flutter web + /releases/
                                                              └─ api.cultur.eqnox.com → cultur-api :8787
```

## 1. Cloudflare dashboard (UI 2025+)

Use **Published application routes**, not **Hostname routes**.

| Menu | Use for cultur? |
|------|-----------------|
| **Networks → Connectors →** *Tunel-HA* → **Published application routes** | Yes — site público na Internet |
| **Networks → Routes → Hostname route** | No — routing WARP / rede privada (modal do “device profile”) |

### Add routes (inside the tunnel)

1. [Cloudflare One](https://one.dash.cloudflare.com/) → **Networks** → **Connectors**
2. Click your tunnel (**Tunel-HA**), not “Create hostname route” on the Routes page
3. Tab **Published application routes** → **Add a published application route**
4. Add twice:

| Subdomain / host | Service type | URL |
|------------------|--------------|-----|
| `cultur` @ `eqnox.com` | HTTP | `http://127.0.0.1:8081` (or your `CULTUR_HTTP_PORT`) |
| `api.cultur` @ `eqnox.com` | HTTP | `http://127.0.0.1:8081` |

Set `CULTUR_HTTP_PORT` in Portainer to the port Caddy uses (e.g. **8081** if 8080 is busy). The Cloudflare tunnel must use the **same** port on `127.0.0.1`.

Cloudflare creates the DNS CNAME **only if** the zone `eqnox.com` is managed in Cloudflare DNS.

If your domain uses **external nameservers** (e.g. HostPapa), you must add CNAME records manually:

| Name | Type | Target |
|------|------|--------|
| `cultur` | CNAME | `<TUNNEL_ID>.cfargotunnel.com` |
| `api.cultur` | CNAME | `<TUNNEL_ID>.cfargotunnel.com` |

Find `<TUNNEL_ID>` in Zero Trust → Connectors → *Tunel-HA* → overview / DNS routes.

Check: `./deploy/scripts/check-dns.sh` — if you see `NXDOMAIN`, the site will not load in the browser.

Full local + public check: `./deploy/scripts/verify-stack.sh`

## 2. cloudflared on the server

Install and run `cloudflared` (systemd service or Docker). Example config: [`../cloudflared/config.yml.example`](../cloudflared/config.yml.example).

Both hostnames must target **the same** local URL (`http://127.0.0.1:8080` by default) so Caddy can split traffic by `Host`.

## 3. Start cultur (tunnel mode)

```bash
./deploy/scripts/build-web.sh

cd deploy
docker compose -f docker-compose.yml -f docker-compose.cloudflare.yml up -d --build
```

This binds Caddy to `127.0.0.1:80` only and uses `Caddyfile.tunnel` (HTTP, no ACME).

## 4. `deploy/.env`

Keep the public URLs on **https** (what users see in the browser):

```env
CULTUR_DOMAIN=cultur.eqnox.com
CULTUR_API_DOMAIN=api.cultur.eqnox.com
ACME_EMAIL=   # leave empty in tunnel mode

CULTUR_DEFAULT_API_URL=https://api.cultur.eqnox.com
CULTUR_ANDROID_APK_URL=https://cultur.eqnox.com/releases/cultur.apk
```

Rebuild web after changing URLs: `./deploy/scripts/build-web.sh`

## 5. Cloudflare SSL mode

In **SSL/TLS** → **Overview**, set encryption mode to **Full** (not “Full (strict)” unless you add a origin cert on Caddy).

Origin is plain HTTP on `127.0.0.1:80` — that is expected.

## 6. Verify

```bash
curl -sS https://api.cultur.eqnox.com/backend/health
curl -sS -o /dev/null -w '%{http_code}\n' https://cultur.eqnox.com/
```

Local (bypass Cloudflare):

```bash
curl -H 'Host: api.cultur.eqnox.com' http://127.0.0.1/backend/health
```

## Common mistakes

| Problem | Cause |
|--------|--------|
| NXDOMAIN in Caddy logs | Using default `Caddyfile` + ACME; switch to `docker-compose.cloudflare.yml` |
| TLS error in browser | Tunnel not running or hostname not in tunnel ingress |
| API CORS / wrong URL in app | Rebuild web with `CULTUR_DEFAULT_API_URL=https://api...` |
| `address already in use` on :80 | Another service uses port 80; use `CULTUR_HTTP_PORT=8080` (default) and point tunnel to `:8080` |
| 502 from Cloudflare | Tunnel URL port ≠ `CULTUR_HTTP_PORT`, or compose not using tunnel override |

## Optional: API directly (skip Caddy for API)

In tunnel ingress you can set `api.cultur.eqnox.com` → `http://127.0.0.1:8787` instead of `:80`. Then only the web hostname goes through Caddy. The monorepo default keeps both on Caddy for one config file.
