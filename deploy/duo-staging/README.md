# duo-staging — artefatos de deploy

Desenho: [ADR-022](../../docs/adr/ADR-022-ambiente-duo-staging-isolado.md) ·
plano: [docs/plan/staging](../../docs/plan/staging/README.md).

| Arquivo | Papel |
|---|---|
| `docker-compose.yml` | Stack inteiro (gateway, 5 serviços, Postgres, Redis, MinIO, one-shots). Vai para `/opt/duo-staging/`. |
| `.env.example` | Modelo do `.env` (domínio, senhas, JWT, Resend). O real fica só na VPS, `chmod 600`. |
| `deploy.sh` | Ordem do deploy: dados → bucket → migrations (identity 1º) → senha da `duo_app` + seed → serviços. Idempotente. |
| `initdb/01-create-dbs.sql` | Cópia de `backend/scripts/create-dbs.sql` (1º boot do volume do Postgres). |
| `gateway/` | Caddy interno + build web. Roteia por Host; bloqueia `/internal/*`. |
| `build-web.sh` | `flutter build web` com as URLs do domínio embutidas. |
| `docker-compose.local.yml` | Override só para testar no Mac (publica 8080, simula o hairpin). |

Imagens: `backend/Dockerfile` (`--build-arg SERVICE=<svc>`, contexto
`backend/`) e `gateway/Dockerfile` (contexto nomeado `web`).

## Testar o stack na máquina de dev

```bash
docker network create edge          # 1ª vez
cd deploy/duo-staging
DUO_BASE=duo-staging.localhost PUBLIC_SCHEME=http PUBLIC_PORT=:8080 ./build-web.sh
docker build --build-context web=../../app/build/web -t ghcr.io/marcus-coube/duo-gateway:local gateway
for s in identity workout assessment comms billing; do
  docker build --build-arg SERVICE=$s -t ghcr.io/marcus-coube/duo-$s:local ../../backend
done
cp .env.example .env.local   # DUO_BASE=duo-staging.localhost, PUBLIC_SCHEME=http,
                             # PUBLIC_PORT=:8080, TAG=local + senhas/JWT
SKIP_PULL=1 COMPOSE_FILE=docker-compose.yml:docker-compose.local.yml \
  COMPOSE_ENV_FILES=.env.local ./deploy.sh
```

App em `http://app.duo-staging.localhost:8080`. Derrubar:
`docker compose -p duo-staging down` (`-v` apaga os dados).

## Na VPS

`cd /opt/duo-staging && ./deploy.sh` (rollback: `TAG=<sha> ./deploy.sh`).
Primeira vez: plano S5.
