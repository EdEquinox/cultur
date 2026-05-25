#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_ENV="$ROOT/deploy/.env"
APP_DIR="$ROOT/cultur_app"
OUT_DIR="$ROOT/deploy/data/web"

if [[ ! -f "$DEPLOY_ENV" ]]; then
  echo "Missing $DEPLOY_ENV — copy deploy/.env.example first." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$DEPLOY_ENV"
set +a

defines=()
if [[ -n "${CULTUR_DEFAULT_API_URL:-}" ]]; then
  defines+=(--dart-define="CULTUR_DEFAULT_API_URL=${CULTUR_DEFAULT_API_URL}")
fi
if [[ -n "${CULTUR_ANDROID_APK_URL:-}" ]]; then
  defines+=(--dart-define="CULTUR_ANDROID_APK_URL=${CULTUR_ANDROID_APK_URL}")
fi

cd "$APP_DIR"
flutter pub get
flutter build web --release "${defines[@]}"

mkdir -p "$OUT_DIR"
rm -rf "${OUT_DIR:?}/"*
cp -a build/web/. "$OUT_DIR/"
echo "Web build copied to $OUT_DIR"
