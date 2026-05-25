# O que vai (e não vai) para o GitHub

O ficheiro `docker-compose.portainer.yml` **só descreve** o deploy. O `git push` envia **ficheiros do repo**, não volumes nem secrets.

## Vai no push (Git)

| Caminho | Uso |
|---------|-----|
| `deploy/docker-compose.portainer.yml` | Stack Portainer |
| `deploy/scripts/*.sh` | Build web, DNS, verificação |
| `deploy/portainer.env.example` | Modelo de vars para a UI |
| `deploy/.env.example` | Modelo deploy |
| `deploy/data/web/.gitkeep` | Pasta vazia (placeholder) |
| `deploy/releases/.gitkeep` | Pasta APK |
| `cultur_backend/` | Código da API (build no GitHub CI → `cultur-api` image) |
| `cultur_app/` | Código Flutter (build no GitHub CI → `cultur-web` image) |

## Não vai no push (`.gitignore` — normal)

| Caminho | Onde criar |
|---------|------------|
| `deploy/.env` | Portainer UI ou servidor |
| `cultur_backend/.env` | Portainer UI ou servidor |
| `deploy/data/web/*` (exceto `.gitkeep`) | Build automático: contentor `cultur-web` no stack Portainer |
| `deploy/releases/*.apk` | Incluído na imagem `cultur-web` do GHCR (CI) |
| `cultur_backend/data/` | Runtime da API |

## O que o Portainer precisa no servidor

Só o ficheiro compose (Git ou colado na UI) + variáveis na UI. **Não** precisa de clonar `cultur_app/` nem `cultur_backend/` para build.

```
deploy/docker-compose.portainer.yml   ← stack Portainer
```

Imagens puxadas automaticamente:

- `ghcr.io/edequinox/cultur-web:main`
- `ghcr.io/edequinox/cultur-api:main`

Dados persistentes: volumes Docker `postgres-data` e `cultur-api-data`.
