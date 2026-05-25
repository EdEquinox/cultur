# Sem espaço em disco no Docker (`no space left on device`)

O build Flutter (`Dockerfile.web`) precisa de **vários GB** (imagem `flutter:stable` + JDK). Em servidores com pouco disco, o Portainer falha ao fazer deploy.

## Solução recomendada (sem build no servidor)

O stack por defeito **só faz pull** da imagem já construída no GitHub:

```text
ghcr.io/edequinox/cultur-web:main
```

1. Faz push para `main` → corre o workflow **Publish web image**
2. GitHub → **Packages** → `cultur-web` → **Package settings** → **Change visibility** → Public (ou configura registry no Portainer)
3. No Portainer, **não** uses o overlay `docker-compose.portainer-local-build.yml`
4. Variável opcional: `CULTUR_WEB_IMAGE=ghcr.io/edequinox/cultur-web:main`

## Libertar espaço no servidor

```bash
docker system df
docker system prune -af --volumes   # cuidado: apaga imagens/contentores não usados
docker builder prune -af
df -h /var/lib/docker
```

Reinicia o deploy no Portainer depois de libertar **pelo menos 3–5 GB**.

## Se ainda precisares de build local

Só com disco livre suficiente:

```bash
docker compose -f deploy/docker-compose.portainer.yml \
  -f deploy/docker-compose.portainer-local-build.yml up -d --build
```

Ou continua a usar `deploy/scripts/build-web.sh` no PC e monta `data/web` (stack antigo).
