# P0 — Fundação (infra, identity, Flutter conectado)

Meta da fase: um professor cria a conta da academia, convida um aluno por e-mail
(Resend), o aluno define a senha e ambos logam no app (mobile e web) caindo em
shells distintos por papel. Backend `identity` completo; demais serviços ainda não.

Refs normativas: ADR-001, ADR-002, ADR-011, ADR-013, `backend/README.md`.

---

## - [x] P0.1 Infra local e compose

**Objetivo:** ambiente de dev reprodutível nas duas máquinas (Windows/Mac).
**Entregáveis:**
- `backend/docker-compose.yml` com **Redis 7** (porta 6379) e **MinIO** (9000/9001,
  bucket `lyfta-media` criado via job `mc` no próprio compose).
- `backend/.env.example` global documentando variáveis comuns; `.gitignore` cobrindo
  `.env` (raiz já tem — conferir padrões `backend/**/.env`).
- Verificação de que os 4 bancos existem no Postgres local (`lyfta_identity`,
  `lyfta_workout`, `lyfta_assessment`, `lyfta_comms`) — script idempotente
  `backend/scripts/create-dbs.sql` (`CREATE DATABASE ... ;` com checagem).
**Aceite:** `docker compose up -d` sobe Redis+MinIO; `psql -l` lista os 4 bancos;
console MinIO acessível com o bucket criado.

## - [x] P0.2 Serviço identity — esqueleto + migrations

**Objetivo:** projeto Go do identity de pé com schema inicial.
**Passos:**
1. `backend/identity/`: `go mod init github.com/marcus-coube/lyfta/identity`,
   layout padrão do `backend/README.md`, chi + pgxpool + config por env,
   `GET /healthz`.
2. Migrations (golang-migrate, SQL):
   - `tenants (id uuid pk, name, slug unique, locale, created_at)`
   - `users (id uuid pk, tenant_id fk, email, password_hash, name, locale,
     status: invited|active|disabled, created_at)` — **unique (tenant_id, email)**
     (ADR-002: conta por tenant).
   - `user_roles (user_id, role: owner|coach|student)` — usuário pode ter 2 papéis.
   - `refresh_tokens (id, user_id, token_hash, expires_at, revoked_at)`
   - `invitations (id, tenant_id, email, role, token_hash, invited_by, expires_at,
     accepted_at)`
   - `password_resets (id, user_id, token_hash, expires_at, used_at)`
   - RLS: habilitar em todas as tabelas com `tenant_id`; policy por
     `current_setting('app.tenant_id')`; role da aplicação sem BYPASSRLS.
3. Middleware: request-id, logging estruturado (slog), recover, CORS (origens via env).
**Aceite:** `migrate up` roda limpo nos 4 ambientes de tabela; `go run ./cmd/api`
responde `/healthz`; teste de repo cria tenant+user respeitando RLS.

## - [x] P0.3 identity — signup, login, refresh, JWT

**Objetivo:** autenticação real conforme ADR-002.
**Endpoints:**
- `POST /v1/tenants` (público): signup do professor/academia — cria tenant + user
  owner (roles `owner`+`coach`) numa transação. Body: nome do negócio, slug, nome,
  email, senha (argon2id).
- `POST /v1/auth/login`: email+senha. Busca users por email **entre tenants**; se 1
  match → tokens; se N matches → `409 code:multiple_tenants` com lista
  `[{tenant_id, tenant_name}]`; cliente reenvia com `tenant_id`.
- `POST /v1/auth/refresh`: rotação de refresh token (hash em banco, revoga o usado).
- `POST /v1/auth/logout`: revoga o refresh token.
- JWT access (15 min, EdDSA): claims `sub`, `tenant_id`, `roles`, `locale`, `exp`.
  Par de chaves ed25519 gerado por script `backend/scripts/gen-keys.sh`, PEM via env.
**Aceite:** testes de handler: signup→login→refresh→logout; login com múltiplos
tenants; senha errada retorna `401 code:invalid_credentials`; access token expirado
rejeitado.

## - [ ] P0.4 identity — convites (Resend) e recuperação de senha

**Objetivo:** o professor convida o aluno por e-mail; aluno ativa a conta.
**Passos:**
1. Cliente Resend (`RESEND_API_KEY`, remetente via env `MAIL_FROM`). Interface
   `Mailer` com implementação `resendMailer` + `logMailer` (dev sem chave: loga o
   link no stdout — dev não depende de e-mail real).
2. `POST /v1/invitations` (auth: owner|coach): cria user `status=invited` + registro
   em `invitations`, envia e-mail com link
   `APP_URL/#/invite?token=...` (template pt-BR simples, HTML inline).
3. `POST /v1/invitations/accept` (público): token válido → define senha, ativa user,
   marca `accepted_at`, retorna tokens (auto-login).
4. `POST /v1/auth/forgot-password` (público, resposta sempre 200) e
   `POST /v1/auth/reset-password` (token). E-mail via Resend, mesmo padrão.
5. Reenvio de convite: `POST /v1/invitations/{id}/resend` (invalida token anterior).
**Aceite:** fluxo completo com `logMailer` nos testes; tokens têm hash em banco,
expiram (convite 7d, reset 1h) e são de uso único.

## - [ ] P0.5 Flutter — núcleo de app: config, HTTP, i18n, roteamento

**Objetivo:** fundação do cliente antes de qualquer tela nova.
**Passos:**
1. Dependências (pinadas): `flutter_riverpod`, `go_router`, `dio`,
   `flutter_secure_storage`, `intl` + ARB (`flutter_localizations`).
2. `lib/core/config/`: base URLs dos 4 serviços via `--dart-define` com defaults
   localhost (8081–8084); `lib/core/http/`: Dio com interceptor de auth (Bearer +
   refresh automático em 401 + fila de retry) e mapeamento do envelope de erro
   (`code`+`params` → mensagem i18n).
3. i18n: `l10n.yaml`, ARBs `app_pt.arb` (fonte), `app_pt_PT.arb`, `app_en.arb`;
   migrar as strings da tela de login existente para ARB. Guard de CI: script
   `tool/check_hardcoded_strings.(sh|ps1)` que falha se achar `Text('` /
   `Text("` literal fora de `design_system/` (aproximação até custom_lint).
4. `go_router`: rotas `/login`, `/invite`, `/forgot`, `/home` com redirect por
   estado de auth (Riverpod `authControllerProvider`) e por papel: shell do aluno
   × shell do professor (telas placeholder). Usuário coach+student: seletor simples
   de contexto no app bar.
**Aceite:** `flutter analyze` limpo; app roda em Chrome e Android; troca de idioma
do device reflete nos 3 locales; script de strings falha se inserirem literal.

## - [ ] P0.6 Flutter — auth real ponta a ponta

**Objetivo:** ligar a tela de login visual ao identity.
**Passos:**
1. `features/auth/data/`: `AuthRepository` (login, refresh, logout, signup tenant,
   accept invite, forgot/reset) sobre o Dio core; tokens no secure storage
   (mobile) / localStorage com cuidado (web — documentar tradeoff no código).
2. Telas: login (existente, agora funcional, com estado de erro i18n), signup do
   professor (nome negócio/slug/email/senha), aceitar convite (lê token da URL —
   funciona em web e via deep link `lyfta://` no mobile), esqueci/redefinir senha.
   Caso `multiple_tenants`: bottom sheet para escolher o tenant.
3. Shell do professor: navegação lateral (web) / bottom bar (mobile) com destinos
   Alunos · Treinos · Chat (placeholders). Shell do aluno: Hoje · Evolução · Chat ·
   Agenda (placeholders). Ambos responsivos (breakpoint ~840px).
**Aceite:** professor faz signup no web, convida aluno; aluno abre link, define
senha e cai no shell de aluno no Android; sessão sobrevive a restart do app
(refresh automático). Teste de widget: login feliz + erro de credencial.

## - [ ] P0.7 CI

**Objetivo:** portão mínimo de qualidade nas duas frentes.
**Entregáveis:** `.github/workflows/ci.yml` com jobs:
- `backend`: matrix por serviço existente; `go vet` + `go test ./...` (Postgres via
  service container; migrations aplicadas antes dos testes).
- `app`: `flutter analyze`, `flutter test`, script de strings hardcoded.
**Aceite:** pipeline verde no push; falha se qualquer job falhar.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

### P0.1 (2026-07-03)

- Docker/Docker Desktop **não está instalado** nesta máquina (Windows) — `docker`
  não é reconhecido no PowerShell nem no Git Bash, e não há
  `C:\Program Files\Docker\Docker\Docker Desktop.exe`. Não foi possível rodar
  `docker compose config` nem `docker compose up -d`.
- Validação feita sem Docker: `backend/docker-compose.yml` parseado com
  `python -c "import yaml; yaml.safe_load(...)"` — YAML sintaticamente válido,
  chaves top-level `services`/`volumes` presentes. Revisão manual do arquivo
  confirma Redis 7 (6379), MinIO (9000/9001) e job `minio-init` (baseado em
  `minio/mc`) que roda `mc alias set` + `mc mb` (idempotente, ignora erro se o
  bucket já existir) + `mc anonymous set none` no bucket `lyfta-media`.
- **Pendência:** rodar, na primeira vez em que o Docker estiver disponível nesta
  máquina (ou já está disponível no Mac):
  `cd backend && docker compose config` (sintaxe) e `docker compose up -d`
  (sobe). Depois conferir: `docker exec -it lyfta-redis-1 redis-cli ping` →
  `PONG`; console MinIO em `http://localhost:9001` (login `minioadmin`/
  `minioadmin` por padrão) com o bucket `lyfta-media` listado.
- `redis-cli` também não está disponível localmente nesta máquina (fora do
  container) — não é bloqueante, a verificação do Redis é via
  `docker exec ... redis-cli ping` conforme acima.
- Bancos Postgres (`lyfta_identity`, `lyfta_workout`, `lyfta_assessment`,
  `lyfta_comms`) já confirmados existentes nesta máquina em sessão anterior —
  não re-verificado aqui (fora do escopo restante desta tarefa).

### P0.2 (2026-07-03, Mac)

- **Go e golang-migrate não estavam instalados nesta máquina (Mac)** — instalados
  via Homebrew nesta sessão (`brew install go` → 1.26.4; `brew install
  golang-migrate` → 4.19.1) para poder implementar e verificar a tarefa. Registrar
  o mesmo passo se o Windows retomar o trabalho de backend sem Go/migrate.
- **RLS e superusuário:** o Postgres local (`postgres`, `marcus`) é superusuário e
  **sempre ignora RLS**, mesmo com `FORCE ROW LEVEL SECURITY` (isso só afeta o
  dono da tabela, não superusuários). Por isso a migration `0007_app_role` cria a
  role `lyfta_app` (`LOGIN`, `NOBYPASSRLS`) e o serviço/testes devem conectar com
  ela (`DATABASE_URL` em `backend/identity/.env.example` já aponta para
  `lyfta_app`) — conectar como `postgres` faz o teste de isolamento passar
  silenciosamente mesmo com RLS quebrada (foi o que aconteceu na primeira
  tentativa desta tarefa, corrigido antes do commit).
- **Ordem das migrations:** a criação da role/grants (`app_role`) foi colocada
  **por último** (`0007`, depois de todas as tabelas), não junto com `tenants`
  como o plano sugeria em ordem — `GRANT ... ON ALL TABLES IN SCHEMA public`
  precisa que as tabelas já existam; `ALTER DEFAULT PRIVILEGES` sozinho só cobre
  tabelas criadas depois dele pela mesma role, não as anteriores.
- **UUID v7:** Postgres 17 local não tem `uuidv7()` nativo (chega só na v18); os
  ids são gerados na aplicação via `github.com/google/uuid` (`uuid.NewV7()`) e
  passados explicitamente nos `INSERT` — colunas `id UUID PRIMARY KEY` sem
  `DEFAULT`.
- **tenant_id em tabelas sem tenant_id explícito no plano:** o plano listava
  `user_roles (user_id, role)`, `refresh_tokens (id, user_id, token_hash,
  expires_at, revoked_at)` e `password_resets (id, user_id, token_hash,
  expires_at, used_at)` sem `tenant_id`. ADR-001 §1/§3 exige `tenant_id` +
  índice iniciando nele em toda tabela de domínio; adicionei `tenant_id`
  denormalizado de `users` nessas três tabelas (com FK para `tenants` e RLS
  própria) para poder aplicar a policy diretamente, sem subquery a `users` a
  cada acesso. Desvio de detalhe, não de arquitetura — sinalizado aqui em vez
  de decidido silenciosamente.
- Role de app usa senha fixa de dev (`lyfta_app_dev`) via `CREATE ROLE ...
  PASSWORD`, documentada só em `.env.example` (não é segredo real, é dev local).
  Em produção a criação da role/senha deve ser parametrizada — ver quando o
  deploy real for desenhado (fora do escopo do MVP local).
- Verificado localmente (Mac): `migrate up` limpo (7 migrations), `migrate down
  -all` e `up` novamente limpo (reversibilidade confirmada), `go vet ./...`,
  `go build ./...`, `go test ./...` (teste de isolamento cross-tenant em
  `internal/repo/repo_test.go`, conectando como `lyfta_app`) e `go run ./cmd/api`
  respondendo `GET /healthz` com `200 {"status":"ok"}` — tudo verde.
- **Pendência para o Windows:** repetir `brew`-equivalente lá (instalar Go 1.22+
  e golang-migrate), rodar `psql -U postgres -f backend/scripts/create-dbs.sql`
  se ainda não tiver os bancos, e então `cd backend/identity && migrate -path
  migrations -database "$DATABASE_URL" up` (com `DATABASE_URL` apontando para
  `postgres` na primeira vez, para criar a role `lyfta_app`; depois trocar para
  `lyfta_app` no `.env`).

### P0.3 (2026-07-03, Mac)

- **RLS vs. lookup de e-mail entre tenants (ADR-002 §2b/2c):** o login precisa
  achar em quais tenants um e-mail existe **antes** de saber qual
  `app.tenant_id` setar. Validado manualmente que, sem esse `SET`, a policy
  `tenant_isolation` de `users` compara `tenant_id` a `current_setting(...)`
  que é `NULL`, e `lyfta_app` vê **0 linhas** mesmo havendo dados — ou seja,
  RLS bloqueia por padrão o próprio caso de uso que o login precisa resolver.
  Solução adotada: migration `0008_email_lookup` cria a função SQL
  `find_tenants_by_email(email)`, `SECURITY DEFINER` (de propriedade do dono
  das tabelas, não de `lyfta_app`), com superfície mínima — devolve só
  `(user_id, tenant_id, tenant_name)`, nunca `password_hash` ou qualquer outra
  coluna. `lyfta_app` só recebe `EXECUTE` nela, não `SELECT` direto fora do
  tenant setado. É a única exceção documentada ao modelo de RLS; todo o resto
  do acesso a dados continua via `WithTenant` (ADR-001 §4: RLS é rede de
  segurança, filtro explícito continua obrigatório em todo o resto).
- **Signup transacional (tenant + owner):** o plano pedia "cria tenant + user
  owner numa transação". `TenantRepo.CreateWithOwner` abre uma única
  transação: insere `tenants` (tabela global, sem RLS), seta
  `app.tenant_id` nessa mesma tx e insere `users`+`user_roles` (com RLS) antes
  do commit — testado em `internal/repo/repo_test.go`
  (`TestCreateTenantWithOwnerTransactional`) que um papel inválido reverte
  tudo, sem deixar tenant órfão.
- **Senha:** argon2id via `golang.org/x/crypto/argon2` (extensão oficial do
  Go, não é dependência de terceiros fora do ecossistema padrão), hash
  autodescritivo (`$argon2id$v=...$m=...,t=...,p=...$salt$hash`), comparação
  em tempo constante (`crypto/subtle`). Parâmetros: OWASP recomendado (64 MiB,
  1 iteração, 4 threads) para uso interativo.
- **JWT:** `golang-jwt/jwt/v5` (pinado no backend/README.md), EdDSA/ed25519,
  claims `sub`, `tenant_id`, `roles`, `locale`, `exp`/`iat`. TTL do access
  15 min (`security.AccessTokenTTL`). Chaves via PEM em env
  (`JWT_PRIVATE_KEY`/`JWT_PUBLIC_KEY`), geradas por `backend/scripts/gen-keys.sh`
  (novo, usa `openssl genpkey -algorithm ed25519`).
- **Refresh token:** opaco (32 bytes aleatórios, base64url), hash SHA-256 em
  banco (nunca o valor em claro), TTL **30 dias** — não especificado no plano,
  adotado como padrão razoável; revisar se o produto pedir "lembrar de mim"
  com TTL diferenciado. Rotação: `POST /v1/auth/refresh` sempre revoga o token
  usado e emite um par novo (access+refresh); reuso do token antigo depois da
  rotação (ou depois de `logout`) responde `401 invalid_token`.
- **Envelope de erro:** `internal/http/apierror.go` centraliza os `code`s
  usados nesta tarefa: `invalid_body`, `validation_error` (com `params.field`),
  `invalid_credentials`, `multiple_tenants` (com `params.tenants[]`),
  `invalid_token`, `slug_taken`, `internal_error`. Login nunca diferencia
  "e-mail não existe" de "senha errada" (sempre `invalid_credentials`) — evita
  vazar quais e-mails têm conta.
- **`.env.example` do identity já tinha os placeholders de `JWT_PUBLIC_KEY`/
  `JWT_PRIVATE_KEY`** (deixados pelo P0.2 apontando para esta tarefa) — nada a
  mudar ali além de gerar o par local com o novo `gen-keys.sh`. PEMs são
  distribuídos como uma linha só com `\n` escapado (formato comum em painéis
  de env tipo Heroku/Render); `config.Load()` desescapa antes do parse
  (`unescapeNewlines`).
- Verificado (Mac): `go build`/`go vet`/`gofmt -l` limpos; `migrate up`
  (8 migrations), `down -all` e `up` de novo limpos (reversibilidade total,
  incluindo a função nova); `go test ./...` verde — cobre signup→login→
  refresh→logout, múltiplos tenants (409), senha errada e e-mail inexistente
  (ambos `401 invalid_credentials`), token expirado rejeitado, e o teste de
  isolamento cross-tenant do P0.2 continua passando. Smoke test manual via
  `curl` do fluxo completo antes de escrever os testes automatizados.
- **Pendência:** nenhum endpoint autenticado existe ainda para exercitar
  `security.JWTSigner.Parse` num middleware real (isso chega em tarefas
  seguintes, quando houver rota protegida por Bearer token). Não há proteção
  de rate limit no lookup de e-mail entre tenants nem no login — ADR-002 §2c
  menciona rate limit como requisito da resolução de e-mail; avaliar onde
  encaixar (provavelmente P0.7/infra ou um ADR de rate limiting, fora do
  escopo desta tarefa).
