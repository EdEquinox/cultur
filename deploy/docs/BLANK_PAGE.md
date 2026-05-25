# Página em branco em cultur.eqnox.pt

O túnel e o Caddy estão OK (HTTP 200), mas o ecrã fica branco quando o **Flutter web não carrega** — quase sempre faltam ficheiros no `cultur-web` ou o pedido não chega ao contentor certo.

## 1. No servidor (SSH)

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep cultur
```

Tem de existir **`cultur-cultur-web-1`** (Up).

```bash
docker exec cultur-cultur-web-1 ls -lh /usr/share/nginx/html/index.html /usr/share/nginx/html/main.dart.js
```

| Ficheiro | Tamanho esperado |
|----------|------------------|
| `index.html` | ~1.5 KB |
| `main.dart.js` | **vários MB** (ex. 3–5 MB) |

Se `main.dart.js` **não existir** ou for **0 bytes** → imagem GHCR errada ou stack antigo sem `cultur-web`.

```bash
curl -sS -H 'Host: cultur.eqnox.pt' http://192.168.1.230:8081/main.dart.js | wc -c
```

Tem de imprimir um número **grande** (milhões), não `0`.

## 2. Stack antigo na porta 8081

Se ainda corre um Caddy **manual** com `data/web` incompleto (só `index.html` ~1504 bytes, sem `main.dart.js`), vês **página branca**.

```bash
docker ps | grep -E 'caddy|cultur'
```

Só deve haver **um** stack Portainer `cultur` com **cultur-web** (imagem GHCR). Para o compose antigo:

```bash
cd /caminho/para/deploy && docker compose down
```

## 3. Portainer — vars + Caddy

```env
CULTUR_DOMAIN=cultur.eqnox.pt
CULTUR_API_DOMAIN=api.cultur.eqnox.pt
CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main
```

Caddy faz `reverse_proxy cultur-web:80` por **Host** (`:80` + `host {$CULTUR_DOMAIN}`).

Se `curl -H 'Host: cultur.eqnox.pt' http://192.168.1.230:8081/ | wc -c` der **0**:

```bash
docker exec cultur-caddy-1 env | grep CULTUR_
docker exec cultur-caddy-1 cat /etc/caddy/Caddyfile
docker exec cultur-caddy-1 wget -qO- http://cultur-web:80/ | wc -c
```

- `wget` para `cultur-web` ~1500 mas curl na 8081 = 0 → domínio no Caddy errado; atualiza o compose (bloco `:80` com `@web host`) e redeploy.
- `wget` para `cultur-web` também 0 → rede entre contentores (raro).

## 4. Rebuild da imagem web (GitHub)

1. **Settings → Actions → Variables**:
   - `CULTUR_DEFAULT_API_URL` = `https://api.cultur.eqnox.pt`
   - `CULTUR_ANDROID_APK_URL` = `https://cultur.eqnox.pt/releases/cultur.apk`
2. Push para `main` (ou re-run workflow **Publish web image**).
3. Portainer → **Pull and redeploy**.

## 5. Browser

1. F12 → **Console** — erros `main.dart.js` 404, `canvaskit`, CORS?
2. **Network** → `main.dart.js` → status **200** e tamanho em MB.
3. Hard refresh: **Ctrl+Shift+R** (service worker antigo pode prender página vazia).

## 6. API

A app pode abrir mesmo sem API; se só vês branco, o problema é quase sempre **ficheiros web**, não a API.

Teste API à parte:

```bash
curl -sS https://api.cultur.eqnox.pt/backend/health
```
