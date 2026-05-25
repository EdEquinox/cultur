# cultur no Portainer

Sim — **é mais fácil no dia a dia** se já usas Portainer. Continua a ser o mesmo Docker Compose; só mudas a forma de o gerir.

O Portainer **não substitui**:

- **Cloudflare Tunnel** (ingress `http://127.0.0.1:8080`)
- **DNS** (CNAME `cultur` / `api.cultur` → túnel) — sem isto o browser não abre o site
- **Build da web** (`./deploy/scripts/build-web.sh` ou ZIP do GitHub Release)

## 1. Código no servidor

O stack precisa do repositório no disco (build da API e pastas `deploy/data/web`):

```bash
git clone https://github.com/TEU_USER/cultur.git /opt/cultur
cd /opt/cultur
cp cultur_backend/.env.example cultur_backend/.env   # editar
cp deploy/.env.example deploy/.env                   # editar
./deploy/scripts/build-web.sh
```

## 2. Criar stack no Portainer

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

**Importante:** o “stack root” deve ser a pasta `deploy/` do repo (onde estão `Caddyfile.tunnel`, `data/web`, `.env`). No Portainer, ao usar Git, define o **Compose path** como acima; os caminhos `../cultur_backend` resolvem a partir de `deploy/`.

## 3. Variáveis de ambiente (só na UI)

O ficheiro `deploy/docker-compose.portainer.yml` **não usa `env_file:`** — as variáveis vêm **apenas** da secção **Environment variables** do stack no Portainer.

1. Abre `deploy/portainer.env.example`
2. Copia as linhas para Portainer → stack `cultur` → **Environment variables** (formato `KEY=value`, uma por linha)
3. Edita passwords e API keys

**Obrigatórias:** `POSTGRES_PASSWORD`, `SERVER_API_SECRET_KEY`, `CULTUR_DOMAIN`, `CULTUR_API_DOMAIN`, `MUSICBRAINZ_CONTACT`

Não uses o campo “Load variables from .env file” a menos que esse ficheiro exista **no caminho do stack no servidor**. A UI sozinha chega.

`CULTUR_DEFAULT_API_URL` / APK são só para `build-web.sh`, não para o stack Docker.

## 4. Deploy

**Deploy the stack**. A primeira vez faz build da imagem `cultur-api` (demora alguns minutos).

Logs úteis: contentor `cultur-caddy-1`, `cultur-cultur-api-1`.

## 5. Cloudflare (igual)

Túnel **Tunel-HA** → **Published application routes** → ambos para `http://127.0.0.1:8080`.

DNS: CNAME na HostPapa ou zona Cloudflare — ver [`CLOUDFLARE_TUNNEL.md`](CLOUDFLARE_TUNNEL.md).

## Erro: `Caddyfile.tunnel` / mount "not a directory"

Quando o ficheiro **não existe** no servidor, o Docker cria uma **pasta** com esse nome e o deploy falha.

1. No servidor (SSH), remove a pasta errada e redeploy:

```bash
sudo rm -rf /data/compose/70/deploy/Caddyfile.tunnel
```

(substitui `70` pelo ID do teu stack)

2. Usa o `docker-compose.portainer.yml` atualizado (Caddy embutido no compose — já não monta `Caddyfile.tunnel`).

3. Garante que existe **`data/web`** com o build Flutter:

```bash
cd /data/compose/70   # raiz do clone Git
./deploy/scripts/build-web.sh
```

4. Na UI do Portainer, opcionalmente:

```env
CULTUR_DEPLOY_DIR=/data/compose/70/deploy
```

(caminho absoluto à pasta `deploy` do clone)

## 6. Atualizar depois

1. `git pull` em `/opt/cultur` (ou redeploy automático do Portainer)
2. `./deploy/scripts/build-web.sh` quando mudares a app Flutter
3. No Portainer: **Pull and redeploy** ou **Recreate** no stack `cultur`

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
