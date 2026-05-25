# cultur-api unhealthy (Portainer)

Erro típico:

```text
dependency failed to start: container cultur-cultur-api-1 is unhealthy
```

## 1. Ver logs (no servidor)

```bash
docker logs cultur-cultur-api-1 --tail 80
```

| Log | Causa |
|-----|--------|
| `SERVER_API_SECRET_KEY must be set` | Falta `SERVER_API_SECRET_KEY` nas vars do stack |
| `password authentication failed` | `POSTGRES_PASSWORD` no Portainer ≠ password do volume Postgres antigo |
| `pull access denied` / `manifest unknown` | Imagem `cultur-api` ainda não existe no GHCR — faz push + workflow **Publish API image** |
| `could not connect to server` | Postgres ainda não pronto (raro com `depends_on`) |

## 2. Password do Postgres

A URL é montada assim:

```text
postgresql+psycopg://cultur:<POSTGRES_PASSWORD>@postgres:5432/cultur
```

- **`POSTGRES_PASSWORD`** tem de ser **igual** em todo o stack (Postgres + API).
- Se mudaste a password mas o volume `postgres-data` já existia com a password antiga, o Postgres **ignora** a nova → API não liga → unhealthy.

**Opções:**

- Voltar a pôr a password antiga nas vars do Portainer, ou
- Apagar o volume `postgres-data` (perdes dados DB) e redeploy com password nova.

Password com caracteres especiais (`@`, `#`, `%`, `:`) têm de ser **URL-encoded** na URL, ou usa só letras/números na password do stack.

## 3. Imagem GHCR

```bash
docker pull ghcr.io/edequinox/cultur-api:main
```

Package **Public** em GitHub → Packages → `cultur-api`.

## 4. Teste manual

```bash
docker exec cultur-cultur-api-1 python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8787/health').read())"

curl -sS http://127.0.0.1:8787/backend/health
```

- `/health` → 200 = processo OK
- `/backend/health` → 500 = problema de ligação à base de dados

## 5. Healthcheck no compose

O stack usa **`/health`** (sem query à DB). Se ainda falhar, o uvicorn não está a escutar — vê logs no passo 1.

Depois de corrigir vars/imagem: Portainer → stack → **Update the stack** → **Re-pull and redeploy**.
