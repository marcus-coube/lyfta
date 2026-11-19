#!/usr/bin/env sh
# Deploy do duo-staging (ADR-022). Roda NA VPS, em /opt/duo-staging, como o
# usuário de deploy. Idempotente: serve para o 1º boot e para cada release.
#
#   ./deploy.sh            # usa TAG do .env (padrão: staging)
#   TAG=sha-<commit> ./deploy.sh  # rollback para uma imagem anterior
#
# Ordem: dados → bucket → migrations (identity primeiro: cria duo_app) →
# senha real da duo_app + seed → serviços. Qualquer falha aborta antes de
# trocar os serviços que estão no ar.
set -eu
cd "$(dirname "$0")"

dc() { docker compose "$@"; }

if [ "${SKIP_PULL:-}" != 1 ]; then  # SKIP_PULL=1: imagens locais (teste no dev)
  echo "==> pull"
  dc pull --quiet
  dc --profile tools pull --quiet
fi

echo "==> dados"
dc up -d --wait postgres redis minio

echo "==> bucket"
dc run --rm minio-init

echo "==> migrations"
for svc in identity workout assessment comms billing; do
  echo "--- $svc"
  dc run --rm "migrate-$svc"
done

echo "==> role duo_app + seed"
dc run --rm db-setup

echo "==> serviços"
dc up -d --wait --remove-orphans

dc ps
echo "==> ok"
