# cultur no Portainer

Sim — **é mais fácil no dia a dia** se já usas Portainer. Continua a ser o mesmo Docker Compose; só mudas a forma de o gerir.

O Portainer **não substitui**:

- **Cloudflare Tunnel** (ingress `http://127.0.0.1:8080`)
- **DNS** (CNAME `cultur` / `api.cultur` → túnel)

## Imagens GHCR (sem build no servidor)

| Serviço | Imagem | Workflow |
|---------|--------|----------|
| `cultur-web` | `ghcr.io/edequinox/cultur-web:main` | Publish web image (+ APK) |
| `cultur-api` | `ghcr.io/edequinox/cultur-api:main` | Publish API image |

1. Push para `main` → workflows publicam as imagens
2. GitHub → **Packages** → `cultur-web` e `cultur-api` → **Public** (ou registry privado no Portainer)
3. Na UI Portainer:

```env
CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main
CULTUR_API_IMAGE=ghcr.io/edequinox/cultur-api:main
```

Para a web, define em GitHub → **Settings → Secrets and variables → Actions → Variables**:

- `CULTUR_DEFAULT_API_URL`
- `CULTUR_ANDROID_APK_URL`

Secrets da API (TMDB, etc.) continuam só na **UI do Portainer** — não vão na imagem.

Erro `no space left on device`? Ver [`DISK_SPACE.md`](DISK_SPACE.md).

## 1. Criar stack no Portainer

**Stacks** → **Add stack** → nome `cultur`

### Opção A — Git (recomendado)

| Campo | Valor |
|-------|--------|
| Repository URL | URL do repo GitHub |
| Compose path | `deploy/docker-compose.portainer.yml` |
| Authentication | token GitHub se privado |

Ativa **Pull and redeploy** se quiseres updates automáticos ao fazer push.

### Opção B — Web editor

Copia o conteúdo de `deploy/docker-compose.portainer.yml` para o editor.

Com Git, basta o **Compose path** `deploy/docker-compose.portainer.yml`. Não há `build:` no stack — não precisas de `cultur_app/` nem `cultur_backend/` no disco do servidor.

## 2. Variáveis de ambiente (só na UI)

O ficheiro `deploy/docker-compose.portainer.yml` **não usa `env_file:`** — as variáveis vêm **apenas** da secção **Environment variables** do stack no Portainer.

1. Abre `deploy/portainer.env.example`
2. Copia as linhas para Portainer → stack `cultur` → **Environment variables** (formato `KEY=value`, uma por linha)
3. Edita passwords e API keys

**Obrigatórias:** `POSTGRES_PASSWORD`, `SERVER_API_SECRET_KEY`, `MUSICBRAINZ_CONTACT`, `CULTUR_WEB_PORT`, `CULTUR_API_PORT`

Não uses o campo “Load variables from .env file” a menos que esse ficheiro exista **no caminho do stack no servidor**. A UI sozinha chega.

## 3. Deploy

**Deploy the stack**. Só faz **pull** das imagens (segundos), se os packages GHCR existirem e forem públicos.

Logs úteis: `cultur-cultur-web-1`, `cultur-cultur-api-1`, `cultur-caddy-1`.

Variáveis de imagem:

```env
CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main
CULTUR_API_IMAGE=ghcr.io/edequinox/cultur-api:main
```

## 4. Cloudflare (igual)

Túnel **Tunel-HA** → **Published application routes** → **uma porta por serviço** (como `music` / `home`):

```text
cultur.eqnox.pt      → http://192.168.1.230:8081   (web)
api.cultur.eqnox.pt  → http://192.168.1.230:8787   (API — porta diferente)
```

Sem Caddy no stack Portainer — não precisas de `CULTUR_DOMAIN` / `CULTUR_API_DOMAIN`.

DNS: CNAME na HostPapa ou zona Cloudflare — ver [`CLOUDFLARE_TUNNEL.md`](CLOUDFLARE_TUNNEL.md).

## Erro: `Caddyfile.tunnel` / mount "not a directory"

Quando o ficheiro **não existe** no servidor, o Docker cria uma **pasta** com esse nome e o deploy falha.

1. No servidor (SSH), remove a pasta errada e redeploy:

```bash
sudo rm -rf /data/compose/70/deploy/Caddyfile.tunnel
```

(substitui `70` pelo ID do teu stack)

2. Usa o `docker-compose.portainer.yml` atualizado (Caddy embutido no compose — já não monta `Caddyfile.tunnel`).

3. Com o stack novo, a web e a API correm só em imagens GHCR; dados da API em volume `cultur-api-data`.

## 5. Atualizar depois

1. Push para `main` → CI publica novas tags `:main`
2. No Portainer: **Pull and redeploy** no stack `cultur`

## Portainer vs `docker compose` na CLI

| | Portainer | CLI |
|---|-----------|-----|
| Ver logs / reiniciar | UI | `docker compose ...` |
| Atualizar stack | Redeploy | `git pull` + compose up |
| O que corre | Mesmos contentores | Idem |

Podes **parar** o stack antigo criado à mão (`docker compose` na pasta `deploy`) antes de subir no Portainer, para não duplicar Postgres/API.

```bash
cd /opt/cultur/deploy
docker compose -f docker-compose.yml -f docker-compose.cloudflare.yml down
# depois só Portainer gere o stack "cultur"
```
