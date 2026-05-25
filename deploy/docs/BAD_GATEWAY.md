# 502 Bad Gateway (cultur.eqnox.pt / cultur.eqnox.com)

Cloudflare mostra **502** quando o túnel liga ao servidor mas o **origin falha** (porta errada, Caddy em baixo, ou `cultur-web` não está a correr).

**Domínio:** se o browser usa `cultur.eqnox.pt`, as vars Portainer **têm de ser `.pt`**, não `.com`:

```env
CULTUR_DOMAIN=cultur.eqnox.pt
CULTUR_API_DOMAIN=api.cultur.eqnox.pt
```

O Caddy só encaminha pedidos cujo `Host` coincide com essas vars.

## Checklist no servidor (SSH em 192.168.1.230)

### 1. Porta do túnel = porta do Caddy

No Portainer: `CULTUR_HTTP_PORT=8081` (no teu caso).

No Cloudflare → Tunnel → Published application routes (igual a `music` / `home`):

| Hostname | URL |
|----------|-----|
| `cultur.eqnox.pt` | `http://192.168.1.230:8081` |
| `api.cultur.eqnox.pt` | `http://192.168.1.230:8081` |

O Caddy tem de estar acessível nesse IP:porta (compose Portainer publica `${CULTUR_HTTP_PORT}:80` na LAN, **não** só `127.0.0.1`).

Teste: `curl -H 'Host: cultur.eqnox.pt' http://192.168.1.230:8081/` → **200**.

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
  -H 'Host: cultur.eqnox.pt' http://127.0.0.1:8081/

curl -sS -o /dev/null -w 'api: %{http_code}\n' \
  -H 'Host: api.cultur.eqnox.pt' http://127.0.0.1:8081/backend/health
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
CULTUR_DOMAIN=cultur.eqnox.pt
CULTUR_API_DOMAIN=api.cultur.eqnox.pt
CULTUR_HTTP_PORT=8081
CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main
```

## Túnel certo + testes no servidor OK + browser 502

O `127.0.0.1:8081` no painel Cloudflare é o **localhost da máquina onde o processo `cloudflared` corre**, não “qualquer servidor onde o Docker está OK”.

### A) `cloudflared` dentro de Docker

Dentro do contentor, `127.0.0.1:8081` é o **próprio contentor**, não o host onde o Portainer publicou o Caddy.

**Teste decisivo** (na máquina do túnel):

```bash
docker ps | grep -i cloudflared
docker exec <nome-ou-id-cloudflared> wget -qO- --header='Host: cultur.eqnox.pt' http://127.0.0.1:8081/ | head
```

- Se **falhar** aqui mas `curl` no host funcionar → altera a rota no Cloudflare para uma destas URLs (a que funcionar no `docker exec`):

| URL no tunnel | Quando usar |
|---------------|-------------|
| `http://172.17.0.1:8081` | Docker default bridge no Linux |
| `http://host.docker.internal:8081` | Docker recente com `host-gateway` |
| `http://192.168.1.230:8081` | IP LAN do host (e Caddy tem de escutar nessa interface — ver B) |

Ou corre `cloudflared` com **`network_mode: host`** para `127.0.0.1:8081` ser o mesmo loopback do host.

### B) Túnel HA com vários connectors (`Tunel-HA`)

Vários nós “Healthy” mas só **um** tem o stack cultur na porta 8081 → parte do tráfego vai para um connector sem origin → **502**.

Zero Trust → Connectors → **Tunel-HA** → vê cada connector e em que host está. Desativa connectors em máquinas **sem** `curl … :8081` OK, ou instala o stack em todos.

### C) Testaste noutra máquina

`curl` OK no PC de desenvolvimento ≠ `curl` OK em **192.168.1.230** onde o `cloudflared` está ligado. Repete o teste **no mesmo host** do connector:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: cultur.eqnox.pt' http://127.0.0.1:8081/
ss -tlnp | grep 8081
```

### D) Logs do cloudflared

```bash
journalctl -u cloudflared -n 50 --no-pager
# ou
docker logs <cloudflared> --tail 50
```

Procura `Unable to reach the origin service` ou `connection refused` → confirma A ou B.

### E) Vars Portainer (Host do Caddy)

Mesmo com túnel certo, no Portainer:

```env
CULTUR_DOMAIN=cultur.eqnox.pt
CULTUR_API_DOMAIN=api.cultur.eqnox.pt
```

## Parar stack antigo (conflito)

Se ainda corre um compose manual na mesma máquina:

```bash
docker compose -f deploy/docker-compose.yml down
```

Só deve haver **um** Caddy cultur na porta 8081.
