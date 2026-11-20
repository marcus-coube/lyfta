#!/usr/bin/env sh
# Build do Flutter web para o gateway do duo-staging (plano S2). As URLs das
# APIs ficam embutidas no JS (String.fromEnvironment), então o build é por
# domínio. Saída: app/build/web (contexto `web` do gateway/Dockerfile).
#
#   DUO_BASE=duo-staging.exemplo.com.br ./build-web.sh
#   DUO_BASE=duo-staging.localhost PUBLIC_SCHEME=http PUBLIC_PORT=:8080 ./build-web.sh
set -eu
: "${DUO_BASE:?defina DUO_BASE}"
scheme="${PUBLIC_SCHEME:-https}"
port="${PUBLIC_PORT:-}"
url() { echo "$scheme://$1.$DUO_BASE$port"; }

cd "$(dirname "$0")/../../app"
# web/ não é versionado (ADR-014: só android/); no CI gera o scaffold padrão.
[ -d web ] || flutter create . --platforms web --org br.com.duotraining
version=$(sed -n 's/^version: *//p' pubspec.yaml)

flutter build web --release \
  --dart-define=IDENTITY_BASE_URL="$(url identity)" \
  --dart-define=WORKOUT_BASE_URL="$(url workout)" \
  --dart-define=ASSESSMENT_BASE_URL="$(url assessment)" \
  --dart-define=COMMS_BASE_URL="$(url comms)" \
  --dart-define=BILLING_BASE_URL="$(url billing)" \
  --dart-define=SENTRY_ENVIRONMENT=staging \
  --dart-define=APP_RELEASE="$version" \
  ${SENTRY_DSN:+--dart-define=SENTRY_DSN="$SENTRY_DSN"}
