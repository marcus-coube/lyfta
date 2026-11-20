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

## Decisões (2026-11-19)

| # | Decisão | Resultado |
|---|---|---|
| D1 | Domínio base | **`duotraining.app`** registrado (Cloudflare). `DUO_BASE=staging.duotraining.app` → `app.staging.duotraining.app`, `identity.staging...` etc. DNS-only + Let's Encrypt (o Universal SSL não cobre dois níveis). |
| D2 | E-mail (convite/reset) | **Resend** com `duotraining.app` verificado; `MAIL_FROM=DÜO <no-reply@duotraining.app>`. |
| D3 | Acesso do CI à VPS | Usuário **`duo-deploy`** próprio (grupo docker, `authorized_keys` e login GHCR dele), criado pelo `bootstrap-vps.sh`. |
| D4 | Backup | Pendente (S7): `pg_dump` diário dentro do stack. |
| D5 | Push | Desligado (`FCM_CREDENTIALS_JSON` vazio). |

## Orçamento de recursos

A VPS tem 2 vCPU / 8 GB / 100 GB para **três** projetos: o staging tem teto
somado bem abaixo disso e nunca disputa com produção.

| Contêiner | mem_limit | cpus |
|---|---|---|
| identity | 256m | 0.25 |
| workout, assessment, comms, billing | 96m cada (384m) | 0.1 cada |
| gateway | 128m | 0.1 |
| postgres | 384m | 0.25 |
| redis | 64m | 0.1 |
| minio | 256m | 0.1 |
| **Residentes** | **~1,5 GB** de teto | **1,2 CPU** de teto |
| one-shots do deploy (um por vez) | — | 0.25 |

- **identity:** o argon2id aloca 64 MiB por hash de senha. Com o limite
  antigo de 96m, **dois logins simultâneos mataram o contêiner por OOM**
  (reproduzido no Mac, 2026-11-19). Com 256m + `GOMEMLIMIT=200MiB`, quatro
  logins simultâneos passam (~2 s cada); um isolado leva ~0,4 s.
- Medido no Mac em repouso: Go 5–7 MB, Postgres ~85 MB, MinIO ~75 MB,
  gateway ~50 MB. Deploy completo ~50 s.
- **Disco** é o risco compartilhado: mídia de execução (até 20 MB cada) cresce
  no volume do MinIO até expirar (7/30 dias, ADR-020). Alerta no S7.
- Antes do 1º `up`: o `bootstrap-vps.sh` aborta com < 2 GB de RAM livre.

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
  serviços; idempotente, `TAG=sha-<commit>` para rollback) + `.env.example` +
  `initdb/01-create-dbs.sql` + `docker-compose.local.yml` (teste no Mac).
  Como usar: [deploy/duo-staging/README.md](../../../deploy/duo-staging/README.md).
- **Um `.env` só** (em vez de um por serviço): o compose injeta em cada
  contêiner apenas o que ele usa — `JWT_PRIVATE_KEY`/`RESEND_API_KEY` só no
  identity. URLs públicas derivam de `DUO_BASE`; M2M por `http://<svc>:<porta>`.
- **MinIO:** o projeto parou de publicar imagens (Docker Hub e Quay não
  servem mais `minio/minio`). O stack usa a build da Chainguard
  (`chainguard/minio` + `chainguard/minio-client`, recompiladas do fonte AGPL),
  **fixadas por digest**. Sem shell utilitário: healthcheck por `/dev/tcp` do
  bash e bucket via `MC_HOST_local`. O `backend/docker-compose.yml` de dev e o
  CI usam as mesmas imagens (no dev, MinIO como root para abrir os volumes
  criados pela imagem antiga).
- **Verificado no Mac** com `DUO_BASE=duo-staging.localhost`: 9 contêineres
  healthy; 5 migrations e seed (41 exercícios); redeploy sem mudança
  ("no change"); cadastro de owner com CORS; preflight e GET nas APIs;
  presign → PUT direto no MinIO (assinatura validada atrás do gateway,
  CORS do MinIO ok); hairpin do comms para `media.`; `/ws` com 101; login no
  app web e aba Início carregando dos 4 serviços, sem erro no console.

### S4 — Pipeline (GitHub Actions) ✅ (2026-11-20)
- [`.github/workflows/deploy-staging.yml`](../../../.github/workflows/deploy-staging.yml)
  (actionlint ok). **Promover = `git push origin main:staging`** ou rodar à mão.
- GitHub Environment **`duo-staging`**: secrets `VM_HOST`, `VM_USER`,
  `VM_SSH_KEY`, `VM_KNOWN_HOSTS` (`ssh-keyscan <host>` — sem TOFU no runner) e
  var `DUO_BASE`. Jobs que leem isso declaram `environment:`.
- Jobs: 5 imagens Go em matrix + gateway (Flutter 3.44.4, `build-web.sh` com
  `DUO_BASE`) → GHCR com `:staging` e `:sha-<commit>`, label
  `duo.stack=duo-staging`; depois SSH: envia `docker-compose.yml`,
  `deploy.sh`, `initdb/` e `README.md` por `tar` (o `.env` da VPS não é
  tocado) → `TAG=sha-<commit> ./deploy.sh` → `curl` nos `/healthz` pelos
  hosts públicos → prune **só** das imagens com a label e > 7 dias (nada de
  prune global no host compartilhado).
- Sem action de terceiros para SSH: `ssh`/`tar` do runner.
- **Pronto quando:** um push em `staging` sem mudança de código redeploya
  verde de ponta a ponta (depende do S5).

### S5 — Bootstrap na VPS (manual, uma vez) ✅ (2026-11-20, falta o e-mail)
Ordem importa: DNS antes do Caddy (o Let's Encrypt valida por HTTP), Caddy
antes do 1º deploy (o healthcheck do workflow usa os hosts públicos).

1. **DNS (Cloudflare `duotraining.app`):** um registro `A`
   `*.staging` → IP da VPS, **DNS-only (nuvem cinza)**. Conferir:
   `dig +short app.staging.duotraining.app`.
2. **Resend:** criar a conta, adicionar o domínio `duotraining.app`, criar no
   Cloudflare os registros que ele pedir (DKIM/SPF/MX do subdomínio de envio,
   todos DNS-only) e esperar "Verified". Gerar uma API key **só de envio,
   restrita ao domínio**.
3. **Chave do CI** (na máquina de dev, sem passphrase — só o CI usa):
   `ssh-keygen -t ed25519 -N '' -C duo-staging-ci -f ~/.ssh/duo-staging-ci`.
4. **Na VPS, como root:** copiar
   [`deploy/duo-staging/bootstrap-vps.sh`](../../../deploy/duo-staging/bootstrap-vps.sh)
   e rodar `./bootstrap-vps.sh staging.duotraining.app "$(cat ~/.ssh/duo-staging-ci.pub)"`
   (conteúdo da `.pub`). Ele confere a memória livre (aborta < 2 GB), cria o
   `duo-deploy` com a chave do CI, cria `/opt/duo-staging` e gera o `.env`
   com senhas e o par JWT feitos ali (testado num Ubuntu 24.04 descartável;
   rodar de novo não troca segredos). Depois, colar a `RESEND_API_KEY` no
   `/opt/duo-staging/.env`.
5. **GHCR:** `su - duo-deploy -c 'docker login ghcr.io -u marcus-coube'` com
   um PAT clássico só com `read:packages`.
6. **Caddyfile compartilhado:** o script imprime o bloco já com os hosts
   (validado com `caddy validate`). `cp Caddyfile Caddyfile.bak.<data>`, colar
   **no fim**, `caddy validate` e `caddy reload` (gracioso). Até o 1º deploy
   os hosts do DÜO dão 502; nada muda para os outros sites.
   **Armadilha (2026-11-20):** o Caddyfile é montado como arquivo único e
   `:ro`. Se um editor o salvou trocando o inode, o contêiner segue lendo a
   cópia antiga (apagada) e `reload` não vê a edição — conferir com
   `docker exec edge-caddy-1 grep -c duotraining /etc/caddy/Caddyfile`. Saída
   usada: validar o arquivo do host num `caddy:2-alpine` descartável e
   `docker restart edge-caddy-1` (segundos de queda para todos). Nessa
   ocasião entrou junto um bloco pendente do ecoprobe
   (`whatsapp.staging.ecoprobe.com.br`) que nunca tinha ido ao ar.
7. **GitHub:** Environment `duo-staging` com secrets `VM_HOST` (IP),
   `VM_USER=duo-deploy`, `VM_SSH_KEY` (a chave privada do passo 3),
   `VM_KNOWN_HOSTS` (`ssh-keyscan -t ed25519 <IP>`) e var
   `DUO_BASE=staging.duotraining.app`.
8. **1º deploy:** rodar o workflow "Deploy duo-staging" (ou
   `git push origin main:staging`). O `initdb` cria os bancos no 1º boot.
9. Conferir o hairpin:
   `su - duo-deploy -c 'cd /opt/duo-staging && docker compose exec comms wget -qO- https://media.staging.duotraining.app/minio/health/live'`.
10. Registrar a mudança no `vps-infra.md` (§5, §7, §9, §14) do repo onde ele
    vive, incluindo o usuário `duo-deploy`.
- **Execução (2026-11-20):** passos 1–9 feitos; 1º deploy verde no 2º run
  (o 1º falhou por `web/` não versionado — `build-web.sh` agora gera o
  scaffold); 5 `/healthz` e mídia 200 com Let's Encrypt, `/internal/*` 404,
  hairpin ok, mh-blog/ecoprobe 200 após o restart do edge. Falta: convite por
  e-mail no 1º cadastro (S6) e o passo 10.
- **Pronto quando:** `https://app.staging.duotraining.app` abre o login, o
  convite chega por e-mail, e mh-blog/ecoprobe respondem normalmente antes e
  depois do reload.

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
- **Disco:** alerta quando o `/` passar de 80% e relatório do tamanho dos
  volumes do stack (`docker system df -v | grep duo-staging`) — disco cheio
  derruba os três projetos. Se a mídia crescer demais, cota no bucket.
- Runbook em `deploy/duo-staging/README.md`: logs
  (`docker compose logs -f <svc>`), rollback (`docker compose` com
  `TAG=sha-<commit>` anterior), reset total (`down -v`, só com aviso aos
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
