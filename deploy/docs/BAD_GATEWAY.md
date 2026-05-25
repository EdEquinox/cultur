# 502 Bad Gateway em cultur.eqnox.com

Cloudflare mostra **502** quando o túnel liga ao servidor mas o **origin falha** (porta errada, Caddy em baixo, ou `cultur-web` não está a correr).

## Checklist no servidor (SSH em 192.168.1.230)

### 1. Porta do túnel = porta do Caddy

No Portainer: `CULTUR_HTTP_PORT=8081` (no teu caso).

No Cloudflare → Tunnel → Published application routes **ambos**:

```text
http://127.0.0.1:8081
```

Se o túnel apontar para `:8080` e o Caddy estiver em `:8081` → **502**.

### 2. Contentores a correr

```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep cultur
```

Precisas de:

| Contentor | Estado |
|-----------|--------|
| `cultur-caddy-1` | Up |
| `cultur-cultur-web-1` | Up (healthy) |
| `cultur-cultur-api-1` | Up |

Se **`cultur-web` não existir** ou estiver `Exited` → **502** na web.

### 3. Pull da imagem web

```bash
docker pull ghcr.io/edequinox/cultur-web:main
```

Se falhar `denied` ou `not found`:

- GitHub → **Packages** → `cultur-web` → **Public**, ou
- Configura registry `ghcr.io` no Portainer com token GitHub.

### 4. Teste local no servidor (sem Cloudflare)

```bash
curl -sS -o /dev/null -w 'web: %{http_code}\n' \
  -H 'Host: cultur.eqnox.com' http://127.0.0.1:8081/

curl -sS -o /dev/null -w 'api: %{http_code}\n' \
  -H 'Host: api.cultur.eqnox.com' http://127.0.0.1:8081/backend/health
```

- **200** aqui + **502** no browser → túnel/porta Cloudflare errada.
- **502** aqui também → problema Docker (ver logs abaixo).

### 5. Logs

```bash
docker logs cultur-caddy-1 --tail 30
docker logs cultur-cultur-web-1 --tail 30
```

Erros comuns nos logs do Caddy: `dial tcp: lookup cultur-web` ou `connection refused` → `cultur-web` não está na mesma rede/stack.

### 6. Variáveis no Portainer

Obrigatórias para o Caddy:

```env
CULTUR_DOMAIN=cultur.eqnox.com
CULTUR_API_DOMAIN=api.cultur.eqnox.com
CULTUR_HTTP_PORT=8081
CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main
```

## Parar stack antigo (conflito)

Se ainda corre um compose manual na mesma máquina:

```bash
docker compose -f deploy/docker-compose.yml down
```

Só deve haver **um** Caddy cultur na porta 8081.
