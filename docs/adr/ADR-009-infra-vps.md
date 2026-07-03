# ADR-009 — Infraestrutura: VPS único com Docker Compose

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

Dev solo, fase pré-lançamento, custo mensal deve ser baixo e a operação mínima.

## Decisão

1. **Um VPS** (Hetzner/DigitalOcean ou similar, ~4 vCPU/8GB) rodando via Docker Compose:
   - `api` (binário Go único — ADR-006)
   - `postgres` (volume dedicado)
   - `redis`
   - `minio` (S3-compatible) — código usa SDK S3, migrar para S3/R2 real é troca de endpoint
   - `caddy` (reverse proxy, TLS automático, WebSocket passthrough)
2. **Ambientes:** `prod` no VPS; `staging` opcional no mesmo host com compose separado;
   desenvolvimento local com o mesmo compose.
3. **Backups (inegociável):** `pg_dump` diário + envio para storage externo ao VPS
   (ex.: Backblaze B2/R2) com retenção 30 dias; teste de restore mensal documentado.
   Volumes do MinIO inclusos no backup.
4. **CI/CD:** GitHub Actions — testes + build da imagem + deploy por SSH
   (`docker compose pull && up -d`). Migrations rodam no boot da API (golang-migrate),
   com política backward-compatible (expand/contract).
5. **Observabilidade mínima:** logs estruturados (JSON) com coleta simples,
   Sentry (ou GlitchTip) para erros da API e do Flutter, e uptime externo
   (UptimeRobot/healthcheck).

## Consequências

- Custo ~US$30–50/mês; operação de uma pessoa.
- Ponto único de falha aceito nesta fase; o desenho (S3 API, compose, Caddy) permite
  migrar para PaaS/cloud sem mudar o código.
- Gatilho de revisão: >50 tenants ativos ou primeira academia grande pagante.
