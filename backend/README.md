# Lyfta — Backend (microserviços Go)

Arquitetura: [ADR-013](../docs/adr/ADR-013-microservicos-db-por-servico.md) —
4 serviços, cada um com projeto Go e banco PostgreSQL próprios. Hoje vivem neste
repositório; no futuro cada um vira um repositório separado (não criar dependência
de código entre serviços — só HTTP).

## Serviços

| Serviço | Porta | Banco | Responsabilidade |
|---|---|---|---|
| `identity/` | 8081 | `lyfta_identity` | Tenants, usuários, papéis, JWT, convites (Resend), recuperação de senha |
| `workout/` | 8082 | `lyfta_workout` | Biblioteca de exercícios, templates (ADR-004), execução, sync offline (ADR-003), mídia |
| `assessment/` | 8083 | `lyfta_assessment` | Medidas, bioimpedância, fotos de evolução |
| `comms/` | 8084 | `lyfta_comms` | Chat (WS+REST), check-in de treino, push FCM |

## Stack pinada (não trocar sem ADR)

- Go 1.22+, router **chi**, driver **pgx/v5** (pgxpool), migrations **golang-migrate**
  (pasta `migrations/` por serviço, SQL puro).
- JWT **EdDSA (ed25519)** via `golang-jwt/jwt/v5`. `identity` assina; os demais
  validam com `JWT_PUBLIC_KEY` (env). Service-to-service: header `X-Internal-Token`
  comparado com `INTERNAL_TOKEN` (env).
- Multi-tenant: `tenant_id` + **RLS** em toda tabela (ADR-001). A conexão seta
  `SET LOCAL app.tenant_id` por request; policies filtram por
  `current_setting('app.tenant_id')`.
- Erros de API: envelope `{ "code": "...", "params": {...} }` — código estável,
  tradução no cliente (ADR-011). Paginação por cursor. IDs: UUID v7.
- E-mail: **Resend** (só no `identity`).
- Mídia: S3-compatible via presigned URLs (MinIO no dev).

## Layout padrão de cada serviço

```
<svc>/
  cmd/api/main.go        # wiring: config, pool, router, server
  internal/
    config/              # env parsing (envconfig ou manual)
    http/                # handlers, middleware (auth, tenant, logging)
    domain/              # tipos e regras de negócio
    repo/                # acesso a dados (pgx), 1 arquivo por agregado
  migrations/            # NNNN_nome.up.sql / .down.sql
  go.mod
```

## Rodar local

```bash
# 1. Infra auxiliar (Redis + MinIO) — Postgres é o local da máquina
docker compose up -d          # backend/docker-compose.yml

# 2. Migrations (por serviço)
cd identity && migrate -path migrations -database "$DATABASE_URL" up

# 3. Subir um serviço
cd identity && go run ./cmd/api
```

Env por serviço: `.env.example` versionado; `.env` local nunca commitado.
Variáveis comuns: `DATABASE_URL`, `PORT`, `JWT_PUBLIC_KEY` (+ `JWT_PRIVATE_KEY` só
no identity), `INTERNAL_TOKEN`, `S3_*` (workout/assessment/comms),
`RESEND_API_KEY` (identity), `REDIS_URL` (comms).

## Bancos locais

Criados no Postgres local da máquina de dev:
`lyfta_identity`, `lyfta_workout`, `lyfta_assessment`, `lyfta_comms`.
