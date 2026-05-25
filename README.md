# cultur

Self-hosted media tracker: Flutter app (Android + web) and FastAPI backend.

| Path | Role |
|------|------|
| [`cultur_app/`](cultur_app/) | Flutter client |
| [`cultur_backend/`](cultur_backend/) | API, auth, PostgreSQL persistence |
| [`deploy/`](deploy/) | Production stack (Caddy HTTPS, web, APK downloads) |
| [`docs/`](docs/) | Schema and architecture notes |

## Quick start (development)

**Backend**

```bash
cd cultur_backend
cp .env.example .env   # fill secrets and MUSICBRAINZ_CONTACT
docker compose up -d --build
```

**App**

```bash
cd cultur_app
flutter pub get
flutter run
```

On first launch, set the API URL (e.g. `http://localhost:8787` or `https://api.your-domain.com`).

## Production (exposed server + HTTPS)

See [`deploy/README.md`](deploy/README.md). Summary:

1. Point DNS `A` records for your app domain and API subdomain to the server.
2. Copy `deploy/.env.example` → `deploy/.env` and `cultur_backend/.env.example` → `cultur_backend/.env`.
3. Build web (and optionally copy a release APK into `deploy/releases/`).
4. `docker compose -f deploy/docker-compose.yml up -d --build`

Caddy obtains Let's Encrypt certificates automatically. The web build can pre-fill the API URL and APK download link via `--dart-define` (documented in deploy README).

## GitHub

- **CI**: backend tests on push/PR (`.github/workflows/ci.yml`).
- **Releases**: tag `v*` builds web + APK artifacts (`.github/workflows/release.yml`). Copy the APK to `deploy/releases/` on the server or attach from GitHub Releases.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`DECOUPLING.md`](DECOUPLING.md).
