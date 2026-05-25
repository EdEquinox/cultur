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
| `cultur_backend/` | Código da API (build Docker) |
| `cultur_app/` | Código Flutter (build no servidor) |

## Não vai no push (`.gitignore` — normal)

| Caminho | Onde criar |
|---------|------------|
| `deploy/.env` | Portainer UI ou servidor |
| `cultur_backend/.env` | Portainer UI ou servidor |
| `deploy/data/web/*` (exceto `.gitkeep`) | Build automático: contentor `cultur-web` no stack Portainer |
| `deploy/releases/*.apk` | Incluído na imagem `cultur-web` do GHCR (CI) |
| `cultur_backend/data/` | Runtime da API |

## O que o Portainer precisa no disco (clone completo)

```
cultur/                    ← raiz do git clone
├── cultur_backend/        ← build context ../cultur_backend
├── cultur_app/            ← flutter build web
└── deploy/
    ├── docker-compose.portainer.yml
    ├── data/web/          ← gerado por build-web.sh (não vem do Git)
    └── releases/          ← opcional: cultur.apk
```

**Compose path no Portainer:** `deploy/docker-compose.portainer.yml`  
**Variável útil:** `CULTUR_DEPLOY_DIR=/caminho/absoluto/para/cultur/deploy`
