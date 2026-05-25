# Release APKs (optional local override)

Production: the APK is baked into the `ghcr.io/edequinox/cultur-web:main` image at
`/releases/cultur.apk` (built in GitHub Actions). No manual copy needed on the server.

This folder is only for local/dev overrides if you mount it in `docker-compose.yml`
(not used by the default Portainer stack).
