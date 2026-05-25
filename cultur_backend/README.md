# cult.u.r API

This service is the first-party backend for `cult.u.r`.

## Role in the architecture

This service is the app's main contract. The Flutter client depends on its JSON
responses and the backend owns authentication, persistence, and the native
catalog/tracking model.

## What it does

- signs in to Yamtrack with cookies + CSRF
- issues first-party `sessionToken` + `refreshToken`
- persists users, media items, and tracking entries in the database
- exposes a small first-party catalog + tracking surface backed by a database

## Database choice

The default production choice is `PostgreSQL`.

Why:

- better long-term fit for a self-hosted backend than file storage
- handles concurrent requests and future background jobs more safely
- gives you solid indexing and JSON support for provider payloads
- easy to run on a home server with Docker Compose

For quick local experiments, the API falls back to `SQLite` if
`SERVER_API_DATABASE_URL` is not set.

## Boundary rules

- mobile features should be added here before the Flutter app learns source
  integration details
- first-party data should live in the database here, not in the Flutter client
- response shapes should stay stable as internal source integrations evolve
- first-party data should live in the database here, not in the Flutter client

## Environment variables

- `SERVER_API_SECRET_KEY`: required in production for encryption
- `TMDB_API`: TMDB key for movies and later TV. This matches the Yamtrack env var
- `TMDB_LANG`: optional TMDB language/locale. Defaults to `en-US`
- `OMDB_API_KEY`: optional OMDb key for movie enrichment during searches
- `OMDB_API`: optional alias for `OMDB_API_KEY`
- `SERVER_API_DATABASE_URL`: optional. Defaults to a local SQLite file for dev,
  but use PostgreSQL on the home server
- `SERVER_API_HOST`: defaults to `0.0.0.0`
- `SERVER_API_PORT`: defaults to `8787`
- `SERVER_API_DATA_DIR`: defaults to `./data`
- `SERVER_API_SESSION_STORE`: optional explicit path for the session JSON file

## Run locally

```bash
cd cultur_backend
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export SERVER_API_SECRET_KEY="change-me"
export TMDB_API="your-tmdb-key"
uvicorn app.main:app --host 0.0.0.0 --port 8787
```

To force PostgreSQL locally:

```bash
export SERVER_API_DATABASE_URL="postgresql+psycopg://cultur:change-me@localhost:5432/cultur"
```

## Docker

Copy the example env file and fill in your keys:

```bash
cd cultur_backend
cp .env.example .env
```

At minimum, set:

- `SERVER_API_SECRET_KEY`
- `TMDB_API`
- optionally `OMDB_API_KEY`

Then start the stack:

```bash
cd cultur_backend
docker compose up -d --build
```

The included compose file now starts both the API and PostgreSQL.

Persisted data:

- the `postgres-data` volume keeps first-party backend data

## Endpoints

- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /me`
- `GET /backend/health`
- `POST /backend/bootstrap`
- `POST /backend/media`
- `GET /backend/media`
- `PUT /backend/tracking`
- `GET /backend/tracking`

## Current native slice

The native backend slice currently covers:

- bootstrap an owner user with `POST /backend/bootstrap`
- upsert catalog items with `POST /backend/media`
- persist progress/status with `PUT /backend/tracking`
- authenticate users with first-party register/login/refresh/logout endpoints

## Remaining migration debt

Some Yamtrack-era modules still exist in the repository for catalog/history
parsing and should be treated as temporary migration debt. See `../DECOUPLING.md`.
