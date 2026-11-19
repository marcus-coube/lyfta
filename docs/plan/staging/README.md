# Plano — deploy do `duo-staging` (web para testadores)

Objetivo: testadores usam o DÜO **pelo navegador** (aluno e professor) num
ambiente estável, antes de qualquer passo de loja (ADR-015). Desenho em
[ADR-022](../../adr/ADR-022-ambiente-duo-staging-isolado.md); VPS descrita no
`vps-infra.md` do repo ecoprobe-gestao (fonte viva do servidor).

**Regra de ouro:** na VPS só se cria `/opt/duo-staging/` e se **acrescenta um
bloco** ao `/opt/edge/Caddyfile`. Nada em `/opt/data`, `/opt/mh-blog`,
`/opt/ecoprobe-*`, crontab do host ou `authorized_keys` de outros usuários.

## Arquitetura

```
Internet ──443──▶ edge-caddy (/opt/edge, compartilhado)
                     │  1 bloco: *.duo-staging hosts → duo-staging-gateway:8080
                     ▼  rede "edge" (só o gateway entra nela)
            ┌──────────── /opt/duo-staging · rede privada "duo-staging" ─────────────┐
            │ gateway (Caddy interno, roteia por Host + serve o Flutter web)         │
            │   app.        → /srv/web (build do Flutter)                            │
            │   identity.   → identity:8081      comms. → comms:8084 (REST + /ws)    │
            │   workout.    → workout:8082       billing. → billing:8085             │
            │   assessment. → assessment:8083    media. → minio:9000 (presign)       │
            │ postgres:17 (5 bancos duo_*) · redis:7 · minio · migrate-* (one-shot)  │
            └────────────────────────────────────────────────────────────────────────┘
```

Hosts (`<base>` = domínio a decidir, D1): `app.<base>`, `identity.<base>`,
`workout.<base>`, `assessment.<base>`, `comms.<base>`, `billing.<base>`,
`media.<base>`. Ex.: `<base>` = `duo-staging.<seudominio>`.

## Decisões pendentes (bloqueiam S5)

| # | Decisão | Recomendação |
|---|---|---|
| D1 | Domínio base | Subdomínio de um domínio já seu no Cloudflare (`duotraining.app` é placeholder, não registrado). 7 registros A **DNS-only** → IP da VPS. |
| D2 | E-mail (convite/reset) | Resend com o domínio de D1 verificado. Sem isso o identity usa o `log_mailer` e convite só sai pelo log — inviável para testador. |
| D3 | Como o CI entra na VPS | Usuário **novo** `duo-deploy` (grupo docker, `authorized_keys` e login GHCR próprios). Não toca o `deploy` dos outros projetos. Alternativa: deploy manual por script (sem CI) na fase 1. |
| D4 | Backup | Dados de testador são reais (LGPD, ADR-008): serviço `backup` **dentro** do stack, `pg_dump` diário em volume + cópia opcional para bucket próprio. |
| D5 | Push | Desligado (`FCM_CREDENTIALS_JSON` vazio); web não usa push no MVP. |

## Orçamento de recursos

| Contêiner | mem_limit | cpus |
|---|---|---|
| postgres | 384m | 0.5 |
| redis | 64m | 0.25 |
| minio | 256m | 0.25 |
| identity, workout, assessment, comms, billing | 96m cada (480m) | 0.25 cada |
| gateway | 128m | 0.25 |
| **Total** | **~1,3 GB** de teto | — |

Medido no Mac (S3, em repouso): serviços Go 5–7 MB cada, Postgres ~85 MB,
MinIO ~75 MB, gateway ~50 MB — uso real < 300 MB.

Antes do 1º `up`: `free -h` e `docker stats --no-stream` na VPS; se sobrar
< 2 GB livres, parar e rever (staging não pode empurrar produção para o swap).

## Tarefas

### S1 — Imagens dos serviços Go ✅ (2026-11-19)
- `backend/Dockerfile` único (`--build-arg SERVICE=<svc>`, contexto `backend/`):
  Go 1.26.4 → `alpine:3.22` com `ca-certificates`, binário não-root,
  `/migrations` e o `migrate` v4.19.1; só o workout leva `/seed` + `psql`.
  `backend/.dockerignore` tira `.env` e testes.
- 5 imagens de ~25 MB (comprimidas), `/healthz` 200.
- `APP_ENV=production` só muda uma coisa hoje (identity exige Redis); staging
  roda `APP_ENV=staging` com Redis setado.

### S2 — Gateway (Caddy interno + Flutter web) ✅ (2026-11-19)
- `deploy/duo-staging/gateway/` (Caddyfile + Dockerfile `caddy:2.10-alpine`,
  build web pelo contexto nomeado `web`) e `deploy/duo-staging/build-web.sh`
  (dart-defines das 5 URLs, `SENTRY_ENVIRONMENT=staging`, `APP_RELEASE` do
  pubspec).
- Domínio em runtime no gateway (`DUO_BASE`); no app ele é embutido no build.
- `Cache-Control: no-cache` no app; `X-Forwarded-For` reescrito com o IP real
  (edge confiável por `trusted_proxies private_ranges`); **`/internal/*` → 404**
  de fora (antes respondia 401: o M2M só existe na rede do stack).
- Healthcheck em `:8081/healthz`, porta que a edge não alcança por Host.

### S3 — Compose do ambiente ✅ (2026-11-19)
- `deploy/duo-staging/docker-compose.yml` + `deploy.sh` (ordem: dados →
  bucket → migrations com identity 1º → senha real da `duo_app` + seed →
  serviços; idempotente, `TAG=<sha>` para rollback) + `.env.example` +
  `initdb/01-create-dbs.sql` + `docker-compose.local.yml` (teste no Mac).
  Como usar: [deploy/duo-staging/README.md](../../../deploy/duo-staging/README.md).
- **Um `.env` só** (em vez de um por serviço): o compose injeta em cada
  contêiner apenas o que ele usa — `JWT_PRIVATE_KEY`/`RESEND_API_KEY` só no
  identity. URLs públicas derivam de `DUO_BASE`; M2M por `http://<svc>:<porta>`.
- **MinIO:** o projeto parou de publicar imagens (Docker Hub e Quay não
  servem mais `minio/minio`). O stack usa a build da Chainguard
  (`chainguard/minio` + `chainguard/minio-client`, recompiladas do fonte AGPL),
  **fixadas por digest**. Sem shell utilitário: healthcheck por `/dev/tcp` do
  bash e bucket via `MC_HOST_local`. ⚠️ O `backend/docker-compose.yml` de dev
  ainda usa `minio/minio:latest` — só funciona em máquina que já tem a imagem
  (o Windows não tem).
- **Verificado no Mac** com `DUO_BASE=duo-staging.localhost`: 9 contêineres
  healthy; 5 migrations e seed (41 exercícios); redeploy sem mudança
  ("no change"); cadastro de owner com CORS; preflight e GET nas APIs;
  presign → PUT direto no MinIO (assinatura validada atrás do gateway,
  CORS do MinIO ok); hairpin do comms para `media.`; `/ws` com 101; login no
  app web e aba Início carregando dos 4 serviços, sem erro no console.

### S4 — Pipeline (GitHub Actions)
- `.github/workflows/deploy-staging.yml`, gatilho `push` na branch `staging`
  + `workflow_dispatch`. Secrets num **GitHub Environment `duo-staging`**
  (`VM_HOST`, `VM_USER`, `VM_SSH_KEY`) — jobs declaram `environment:`.
- Jobs: matrix build das 5 imagens + gateway → GHCR
  `ghcr.io/marcus-coube/duo-<svc>:staging` e `:<sha>` (gateway: `build-web.sh`
  com `DUO_BASE` de uma variável do Environment); depois SSH →
  `/opt/duo-staging/deploy.sh` (já faz pull, migrations, seed e `up --wait`;
  falha em migrate aborta antes de trocar os serviços) → `curl` nos `/healthz`
  pelos hosts públicos.
- O compose e o Caddyfile do gateway viajam no deploy (`scp` de
  `deploy/duo-staging/` exceto `.env`), para a VPS nunca divergir do git.
- **Pronto quando:** um push em `staging` sem mudança de código redeploya
  verde de ponta a ponta.

### S5 — Bootstrap na VPS (manual, uma vez — depende de D1–D3)
1. DNS: 7 registros A DNS-only (cinza) → IP da VPS.
2. `free -h`; criar `/opt/duo-staging/` (e usuário `duo-deploy`, se D3).
3. Gerar chaves JWT (`backend/scripts/gen-keys.sh`), `INTERNAL_TOKEN` e
   senhas com `openssl rand -hex 32`; preencher `.env` (modelo
   `.env.example`), `chmod 600`.
4. `docker login ghcr.io` com o usuário do deploy (PAT `read:packages`).
5. Copiar `deploy/duo-staging/` (sem `.env.local`) para a pasta e rodar
   `./deploy.sh` (1º boot cria os bancos pelo `initdb`, troca a senha de dev
   da `duo_app` e aplica o seed).
6. Conferir `docker compose ps` todo `healthy` e o hairpin:
   `docker compose exec comms wget -qO- https://media.<base>/minio/health/live`.
7. Caddyfile compartilhado: `cp Caddyfile Caddyfile.bak.<data>`, colar o
   bloco abaixo **no fim**, `caddy validate` e `caddy reload` (gracioso:
   config inválida não aplica e não derruba ninguém).
8. Registrar a mudança no `vps-infra.md` (§5, §7, §14) do repo onde ele vive.
- **Pronto quando:** `https://app.<base>` abre o login, e mh-blog/ecoprobe
  respondem normalmente antes e depois do reload.

### S6 — Smoke e liberação para testadores
- Rodar o roteiro [e2e-25](../mvp25/e2e-25.md) **no Chrome** contra o staging
  (coach e aluno em janelas diferentes): cadastro, convite por e-mail real,
  builder, treino, check-in com mídia (upload direto no MinIO), chat por WS,
  financeiro com baixa manual.
- Criar a organização de teste e convidar os testadores; texto curto de
  boas-vindas com o link e "isso é um ambiente de teste" (termos vigentes
  `TERMS_VERSION` 2026-11-v4).
- **Pronto quando:** roteiro verde e o primeiro testador fez login.

### S7 — Operação mínima
- `backup` no stack (D4): crond interno, `pg_dump -Fc` dos 5 bancos, 7 dias
  em volume; restore ensaiado uma vez.
- Uptime externo (UptimeRobot) em `https://identity.<base>/healthz` e
  `https://app.<base>`.
- Runbook em `deploy/duo-staging/README.md`: logs
  (`docker compose logs -f <svc>`), rollback (`docker compose` com
  `TAG=<sha>` anterior), reset total (`down -v`, só com aviso aos
  testadores), rotação de segredos.
- **Pronto quando:** runbook escrito e restore testado.

### S8 — Docs
- `CLAUDE.md`: ponteiro para este plano e estado do staging.
- ADR-022 → **Aceito** quando S5 fechar.

## Bloco do Caddyfile compartilhado

Bloco a acrescentar no `/opt/edge/Caddyfile` (única alteração fora da pasta):

```caddy
# ============================ DÜO — STAGING (ADR-022 do repo lyfta) ============================
# DNS-only (nuvem cinza) → Let's Encrypt automático. Roteamento interno no gateway do stack.
app.<base>, identity.<base>, workout.<base>, assessment.<base>,
comms.<base>, billing.<base>, media.<base> {
	encode zstd gzip
	log {
		output stdout
		format console
	}
	reverse_proxy duo-staging-gateway:8080
}
```

Caddyfile do gateway e compose: versionados em `deploy/duo-staging/`.

## Riscos

- **RAM da VPS** (8 GB para três projetos) — mitigado pelos `mem_limit` e pela
  checagem do S5.2.
- **Hairpin da mídia:** o presign assina com o host do `S3_ENDPOINT`, então o
  comms também apaga mídia via `https://media.<base>` (sai e volta pela
  `edge`). O Docker faz hairpin NAT por padrão; validar no S5 com
  `docker compose exec comms wget -qO- https://media.<base>/minio/health/live`.
  Se falhar, a saída é separar endpoint de presign e de operação no código
  (tarefa nova, não gambiarra de rede).
- **Rate limit do Let's Encrypt:** 7 certificados novos de uma vez é ok;
  não apagar o volume `caddy-data` do `/opt/edge`.
- **Testador com dado real de saúde** em ambiente de teste — termos vigentes
  cobrem; reset total só com aviso.
