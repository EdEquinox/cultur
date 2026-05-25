# cultur production deploy

Stack: **PostgreSQL** + **API** + **Caddy** (HTTPS, static web, APK downloads).

## Deploy modes

| Mode | When to use | Docs |
|------|-------------|------|
| **Cloudflare Tunnel** | Home server, no open ports | [`docs/CLOUDFLARE_TUNNEL.md`](docs/CLOUDFLARE_TUNNEL.md) |
| **Portainer** | GUI para o mesmo stack | [`docs/PORTAINER.md`](docs/PORTAINER.md) |
| **Direct (Caddy + Let's Encrypt)** | Public IP, ports 80/443 open | below |

```bash
# Cloudflare Tunnel (recommended for home server)
docker compose -f docker-compose.yml -f docker-compose.cloudflare.yml up -d --build
```

## Prerequisites (direct mode only)

- A public server with ports **80** and **443** open.
- **DNS must exist before HTTPS works.** Create A (or AAAA) records pointing at the server IP, for example:
  - `cultur.example.com` — web app + APK at `/releases/`
  - `api.cultur.example.com` — API
- Docker and Docker Compose.

If Caddy logs show `NXDOMAIN` or the browser shows a TLS error, the API may still be fine — only certificates are blocked until DNS propagates. After adding records, run `docker compose restart caddy` and `./deploy/scripts/verify-deploy.sh`.

## 1. Configure secrets

```bash
cp cultur_backend/.env.example cultur_backend/.env
# Edit: SERVER_API_SECRET_KEY, POSTGRES_PASSWORD, TMDB_API, MUSICBRAINZ_CONTACT, etc.

cp deploy/.env.example deploy/.env
# Edit: CULTUR_DOMAIN, CULTUR_API_DOMAIN, ACME_EMAIL
# Optional: CULTUR_DEFAULT_API_URL, CULTUR_ANDROID_APK_URL for web/APK links
```

## 2. Build and publish the web app

From the repo root:

```bash
./deploy/scripts/build-web.sh
```

This runs `flutter build web` with `--dart-define` values from `deploy/.env` and copies output to `deploy/data/web/`.

## 3. Android APK

Build a release APK (locally or from a GitHub Release), then place it on the server:

```bash
cp path/to/cultur.apk deploy/releases/cultur.apk
```

The URL `https://<CULTUR_DOMAIN>/releases/cultur.apk` must match `CULTUR_ANDROID_APK_URL` in `deploy/.env` if you use the in-app download link.

Signing: for everyday use, configure a release keystore in `cultur_app/android/` (not committed). CI builds an unsigned release APK until you add signing secrets.

## 4. Start the stack

If you previously ran the dev stack in `cultur_backend/`, stop it first so container names and port 5432 do not conflict:

```bash
cd cultur_backend && docker compose down
docker rm -f cultur_postgres cultur_api 2>/dev/null || true
```

Then:

```bash
cd deploy
docker compose up -d --build
```

Caddy requests Let's Encrypt certificates on first successful HTTP challenge. Ensure DNS is correct **before** the first start.

## 5. Bootstrap the API

Create the first user via the app (register) or `POST /backend/bootstrap` if you use that flow — see `cultur_backend/README.md`.

## Updating

```bash
./deploy/scripts/build-web.sh
docker compose -f deploy/docker-compose.yml up -d --build cultur-api
docker compose -f deploy/docker-compose.yml restart caddy
```

Copy a new APK to `deploy/releases/` when needed; no container rebuild required.

## MusicBrainz TLS in Docker

If album search fails with TLS errors from MusicBrainz inside the bridge network, switch `cultur-api` in `docker-compose.yml` to `network_mode: host` and set:

```env
SERVER_API_DATABASE_URL=postgresql+psycopg://cultur:PASSWORD@127.0.0.1:5432/cultur
```

Expose PostgreSQL on `127.0.0.1:5432` only if you do this.

## Firewall

Allow inbound **80/tcp** and **443/tcp**. Do not expose PostgreSQL (5432) publicly.
