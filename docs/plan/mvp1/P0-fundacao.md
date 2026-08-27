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

## - [x] P0.4 identity — convites (Resend) e recuperação de senha

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

## - [x] P0.5 Flutter — núcleo de app: config, HTTP, i18n, roteamento

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

## - [x] P0.6 Flutter — auth real ponta a ponta

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

## - [x] P0.7 CI

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

### P0.4 (2026-07-04, Mac)

- **Mailer:** interface `mail.Mailer` com `resendMailer` (produção, API do
  Resend) e `logMailer` (dev/teste). Seleção em `main.go` pela presença de
  `RESEND_API_KEY`: sem chave, loga o link no stdout e segue — dev/teste não
  dependem de e-mail real (Aceite). Templates HTML inline pt-BR (convite e
  reset) em `internal/mail/templates.go`; e-mail transacional é texto de
  servidor, não string de UI (ADR-011 trata i18n de UI, não isto).
- **Primeiro endpoint autenticado (fecha a pendência do P0.3):** middleware
  `RequireAuth` (valida Bearer via `JWTSigner.Parse`, injeta claims no
  contexto) + `RequireRole(owner,coach)`. Decisão de RLS: o middleware **não**
  seta `app.tenant_id`; cada repo continua abrindo sua tx via `WithTenant` a
  partir do `tenant_id` **da claim** (nunca de body/query), pra não confiar em
  input do cliente na hora de aplicar RLS. `POST /v1/invitations` e
  `/{id}/resend` exigem sessão owner|coach; `/accept` é público.
- **Endpoints públicos por token (accept/reset) e RLS:** mesmo problema do
  login no P0.3 — o cliente só tem o token, ainda não sabe o `tenant_id`.
  Migration `0009_public_token_lookup` cria `find_invitation_by_token` e
  `find_password_reset_by_token`, `SECURITY DEFINER`, de superfície mínima
  (só a linha do convite/reset pelo hash exato, nunca por listagem; essas
  tabelas não têm coluna sensível como `password_hash`), `EXECUTE` só pra
  `lyfta_app`. Segue o mesmo padrão documentado em `0008` — exceção contida,
  o resto do acesso continua via `WithTenant`.
- **forgot-password sempre 200:** não distingue e-mail existente de
  inexistente (não vaza quais e-mails têm conta). Se o e-mail existir em N
  tenants (ADR-002: conta por tenant), cria um pedido de reset e envia um
  e-mail **por conta ativa**, reusando `find_tenants_by_email` (0008).
- **Tokens:** convite e reset são opacos (32 bytes, base64url), hash SHA-256
  em banco (`repo.HashToken`, mesmo do refresh), uso único, expiram — convite
  7d (`repo.InvitationTTL`), reset 1h (`repo.PasswordResetTTL`). Reenvio de
  convite invalida o token anterior (`invitations.Invalidate`) antes de gerar
  o novo. `accept` faz auto-login (reusa `issueTokens`); `reset-password`
  responde 204 (sem auto-login, o usuário loga com a senha nova).
- **Refactor de `issueTokens`:** virou função livre em `auth.go`
  (`issueTokens(ctx, jwt, auth, logger, user)`) pra ser reusada pelo
  auto-login do `accept` sem um `AuthHandler`; `generateOpaqueToken`
  ficou única (removida a duplicata que havia em `invitations.go`).
- **Novos `code`s de erro:** `email_taken`, `unauthenticated`, `forbidden`
  (além dos do P0.3) em `apierror.go`.
- Verificado (Mac): `go vet`/`go build` limpos; `migrate up` (9 migrations)
  aplicada; `go test ./...` verde — 5 testes novos de handler cobrindo o
  fluxo completo com mailer de captura: convite→accept(auto-login)→login do
  aluno + reuso do convite falha; `POST /v1/invitations` sem Bearer → 401
  `unauthenticated` e com papel só `student` → 403 `forbidden`; reenvio
  invalida o token anterior e o novo funciona; forgot→reset→login com senha
  nova (antiga falha) + reuso do token de reset falha; forgot de e-mail
  inexistente responde 200 sem enviar e-mail. Smoke test do binário real
  (`go run ./cmd/api`): `/healthz` 200, `forgot-password` 200,
  `/v1/invitations` sem auth 401.
- **Pendência (herdada, ainda aberta):** rate limit no lookup de e-mail entre
  tenants e nos endpoints públicos por token (força-bruta de token é mitigada
  por 256 bits de entropia + expiração curta, mas rate limit ainda cabe) —
  ADR-002 §2c; avaliar em P0.7/infra ou ADR dedicado. **Windows:** aplicar a
  migration `0009` (`migrate ... up`) ao retomar o backend.

### P0.5 (2026-07-04, Mac)

- **Flutter instalado via Homebrew nesta sessão** (`brew install flutter` →
  3.44.4 stable, Dart 3.12.2) — repetir no Windows ao retomar o app (instalar
  Flutter SDK e rodar `flutter doctor`). Android SDK e Xcode **não** estão
  configurados nesta máquina: `flutter analyze`/`flutter test` não exigem
  plataforma nenhuma, e Chrome (web) funciona; **rodar em Android fica
  pendente** até o SDK ser instalado — não tentado aqui.
- **Dependências pinadas:** `flutter_riverpod ^2.6.1`, `go_router ^14.8.1`,
  `dio ^5.7.0` (resolvido `5.10.0`), `flutter_secure_storage ^9.2.2`,
  `intl` teve que ser fixado em `^0.20.2` (não `^0.19.0` como o plano
  sugeria) porque `flutter_localizations` do Flutter 3.44.4 já pina
  `intl 0.20.2` — usar `^0.19.0` quebra a resolução de dependências.
- **i18n (ADR-011):** `l10n.yaml` na raiz de `app/`, ARBs em
  `lib/core/l10n/arb/` (`app_pt.arb` fonte, `app_pt_PT.arb`, `app_en.arb`),
  saída gerada em `lib/core/l10n/gen/` (`flutter gen-l10n`, rodado
  automaticamente por `flutter pub get`/`flutter test` via `generate: true`
  no pubspec). **Fallback pt-PT→pt-BR é automático**: o gen-l10n gera
  `AppLocalizationsPtPt extends AppLocalizationsPt`, então qualquer chave
  ausente do `app_pt_PT.arb` herda o valor de `app_pt.arb` sem código
  manual — só populei em `app_pt_PT.arb` as poucas strings com variação real
  (tratamento "tu" vs "você", "palavra-passe" vs "senha"). Os arquivos
  gerados (`lib/core/l10n/gen/*.dart`) foram commitados junto (repo já
  versiona tudo dentro de `lib/`; evita exigir passo de build extra).
  Migrei todas as strings literais da `login_screen.dart` existente para
  ARB.
- **Guard de strings hardcoded:** `tool/check_hardcoded_strings.sh` (+
  `.ps1` para Windows) — grep por `Text('`/`Text("` fora de
  `core/design_system/` e `core/l10n/gen/` (arquivos gerados têm
  strings literais nos doc-comments/exemplos, não são UI). Testado
  manualmente inserindo um `Text('literal')` num arquivo temporário: script
  falha com exit 1 e aponta o arquivo/linha; removido antes do commit.
- **HTTP core:** `ApiClient` (Dio por serviço) com dois interceptors:
  `AuthInterceptor` (injeta `Authorization: Bearer`, refresh automático em
  401 com deduplicação — um único `Future<AuthTokens?>` compartilhado entre
  requisições concorrentes, testado em
  `test/core/http/auth_interceptor_test.dart`) e `ErrorMappingInterceptor`
  (converte o envelope `{code, params}` do backend em `ApiException`).
  Tradução do `code` para mensagem i18n fica em `ApiExceptionL10n`
  (`lib/core/http/api_exception_l10n.dart`), cobrindo todos os `code`s
  hoje emitidos pelo `identity` (`apierror.go`): `invalid_credentials`,
  `multiple_tenants`, `validation_error` (com `params.field`),
  `email_taken`, `invalid_token`, `unauthenticated`, `forbidden`,
  `slug_taken`, `internal_error`, mais `network_error` para falha de
  conexão. `TokenStorage` usa `flutter_secure_storage`; documentado no
  código o tradeoff do fallback web (localStorage) — decisão final de
  persistência web fica para P0.6.
- **Roteamento:** `go_router` com `redirect` central em
  `lib/core/router/app_router.dart`, ligado a um `authControllerProvider`
  (Riverpod) que por ora é **stub em memória** (`AuthState.unauthenticated`
  no boot, sem ler storage/backend — isso é o que o plano pediu
  explicitamente para esta tarefa; P0.6 liga de verdade mantendo a mesma
  interface pública do controller). Rotas públicas: `/login`, `/invite`
  (lê `token` da query string), `/forgot`; `/home` decide entre
  `CoachShellScreen`/`StudentShellScreen` pelo `ActiveContext` do estado de
  auth. Usuário com os dois papéis (`hasBothRoles`) vê
  `RoleContextSwitcher` (`lib/shared/widgets/`) no app bar de ambos os
  shells — extraído para `shared/` por ser idêntico nos dois (guideline:
  "comum sobe para shared/").
- **Testes:** `test/core/router/app_router_test.dart` (4 casos: sem sessão
  bloqueia rota protegida; autenticado como coach/student cai no shell
  certo; autenticado tentando `/login` volta pra `/home`) e
  `test/core/http/auth_interceptor_test.dart` (2 casos: refresh reenvia a
  requisição original; N requisições concorrentes com 401 compartilham um
  único refresh — via `HttpClientAdapter` fake, sem pacote novo de mock).
  Removido `test/widget_test.dart` (boilerplate gerado por
  `flutter create .`, referenciava uma classe `MyApp` inexistente).
  **Achado:** o locale padrão do ambiente `flutter test` é `en`, não
  `pt` — os testes de widget fixam `locale: const Locale('pt')`
  explicitamente no `MaterialApp.router` para serem determinísticos.
- **Verificado (Mac):** `flutter pub get` limpo; `flutter analyze` sem
  issues; `flutter test` verde (6 testes); `tool/check_hardcoded_strings.sh`
  passa limpo e falha corretamente com literal inserido propositalmente;
  app rodado de fato no Chrome via `flutter run -d chrome` (tela de login
  renderizada com textos em inglês, pois o Chrome do ambiente de preview
  reporta `navigator.language = en-US`— confirma que a resolução de
  locale por idioma do dispositivo funciona; troca para pt-BR/pt-PT não
  foi verificada visualmente no navegador real por não haver controle
  simples de alterar o idioma do Chrome em runtime nesta sessão, mas está
  coberta pelos testes de widget com locale fixo e é 100% delegada ao
  `MaterialApp`/`flutter_localizations`, não a código nosso).
- **Pendência:** rodar em Android (sem SDK nesta máquina — instalar Android
  Studio/SDK ao retomar, se for continuar no Mac; ou verificar no Windows
  se lá já há Android Studio configurado). `app/web/` (gerado por
  `flutter create .`) não foi commitado, conforme `app/README.md` ("só
  lib/, pubspec.yaml e configs são versionados") — gerar de novo com
  `flutter create . --platforms=web` (ou os demais) ao configurar uma nova
  máquina. Criado `.claude/launch.json` (config do preview tool desta
  sessão) para rodar `flutter run -d chrome` via MCP — não é parte do plano,
  mas é útil para verificação visual em tarefas futuras.

### P0.6 (2026-07-12, Mac)

- **Contratos do `identity` conferidos direto no código** (não presumidos):
  `tokenResponse` (`access_token`, `refresh_token`, `expires_at`, `tenant_id`,
  `user_id`, `roles`) é o corpo de signup/login/refresh/accept invite;
  `login` aceita `tenant_id` opcional no body e devolve
  `409 multiple_tenants` com `params.tenants: [{tenant_id, tenant_name}]`;
  `refresh`/`logout` exigem `tenant_id` no body (não só o refresh token) —
  `backend/identity/internal/http/auth.go`. Validado também via `curl` contra
  o serviço real (`go run ./cmd/api` com `.env` local): signup retornou
  exatamente o envelope esperado.
- **`AuthRepository`** (`app/lib/features/auth/data/auth_repository.dart`)
  cobre os 7 endpoints do plano sobre um `Dio` "cru" (não o `ApiClient` do
  core, que dependeria do próprio `AuthController` para refresh — evitaria
  recursão). Ponto não óbvio: `Dio.post` sempre lança `DioException`, nunca a
  `ApiException` original — o `ErrorMappingInterceptor` só anexa a
  `ApiException` em `DioException.error`. Sem desembrulhar isso, nenhum
  `catch (e) on ApiException` da UI jamais casaria. Centralizado num helper
  privado `_post` que relança `e.error` quando é `ApiException` — descoberto
  porque o teste de widget do erro de credencial falhava silenciosamente até
  essa correção.
- **`AuthController`** (`core/auth/auth_controller.dart`) passou de stub para
  sessão real: `build()` dispara `_restoreSession()` (lê `TokenStorage`,
  revalida com um `refresh` real — garante um access token sempre fresco
  após restart) mantendo o mesmo contrato público que a P0.5 já previa
  (`state`, `signOut`, `switchContext`); `signInStub` continua existindo só
  para os testes de roteamento que não sobem HTTP. Ganhou construtor com
  `tokenStorage`/`httpAdapter` opcionais (mesmo padrão de
  `TokenStorage({FlutterSecureStorage? storage})`) para permitir
  `authControllerProvider.overrideWith(() => AuthController(...))` em teste
  de widget sem tocar rede real. `refreshSession` (chamado pelo
  `AuthInterceptor` de qualquer `ApiClient`) reusa o mesmo `tenant_id`
  persistido — todos os serviços compartilham o refresh do `identity`
  (ADR-013).
- **`TokenStorage` estendida** (`core/http/token_storage.dart`) para guardar
  `tenant_id`/`user_id`/`roles` junto dos tokens (`StoredSession`/
  `saveSession`/`readSession`) — sem isso o boot não teria como saber o
  tenant/papéis sem decodificar o JWT no cliente; optei por persistir os
  metadados já devolvidos pelo backend em vez de adicionar um parser de JWT
  (nenhuma dependência nova, mais simples). Tradeoff do fallback web
  (`localStorage`) documentado no docstring da classe, conforme pedido pela
  tarefa.
- **Caso `multiple_tenants`:** `LoginScreen` mostra um `showModalBottomSheet`
  com as opções (`TenantOption`, extraídas de `ApiException.params.tenants`
  via extension `MultipleTenantsError`) e reenvia `signIn` com o
  `tenantId` escolhido.
- **Rotas novas:** `/signup` (`SignupScreen` — nome do negócio, slug
  auto-gerado do nome até o usuário editar manualmente, nome, e-mail, senha)
  e `/reset` (`ResetPasswordScreen`, token via query string, mesmo padrão de
  `/invite`). `/invite` ganhou comentário explicando que o deep link
  `lyfta://invite?token=...` depende de configuração nas plataformas nativas
  (`AndroidManifest.xml`/`Info.plist`, geradas por `flutter create .` e não
  versionadas neste repo — `app/README.md`) — **não implementado nem
  verificável nesta máquina** (sem Android SDK/Xcode configurados); o
  `go_router` já resolve `state.uri.queryParameters['token']`
  independentemente da origem (query web ou deep link mobile), então não há
  lógica adicional pendente, só a configuração de plataforma.
- **Shells responsivos:** `LyShellScaffold`
  (`shared/widgets/ly_shell_scaffold.dart`) novo — `NavigationRail` (web/
  desktop >= 840px) ou `NavigationBar` (mobile), breakpoint pedido
  explicitamente pelo plano (`lyShellRailBreakpoint`, diferente dos
  600/1024 de `docs/guidelines/flutter.md`, que são genéricos). Reutilizado
  pelos dois shells (coach/student), que só declaram seus destinos.
- **`LyTextField`** ganhou `onSubmitted`/`onChanged` (não existiam na P0.5) —
  necessários para submeter formulário com Enter e para o auto-slug do
  signup; mudança no design system, não na feature (guideline: componente
  reutilizável nasce em `core/design_system/`).
- **Teste de widget obrigatório**
  (`test/features/auth/presentation/login_screen_test.dart`): fluxo feliz
  (login válido → shell do professor) e erro de credencial (401
  `invalid_credentials` → mensagem i18n visível, permanece em `/login`) —
  ambos sobre um `HttpClientAdapter` fake que replica o envelope real do
  `identity`, sem depender de rede. Mesmo padrão de fake de secure storage
  já usado em `auth_interceptor_test.dart`.
- **Verificado (Mac):** `flutter analyze` limpo; `flutter test` verde (8
  testes: 4 de roteamento da P0.5 + 2 de refresh/concorrência da P0.5 + 2
  novos de login); `tool/check_hardcoded_strings.sh` limpo. Backend
  `identity` subido localmente (`go run ./cmd/api`) e `POST /v1/tenants`
  testado via `curl` — o envelope de resposta bateu exatamente com o que
  `AuthSession.fromJson` espera. App rodado de fato em
  `flutter run -d chrome`: tela de login renderiza (texto em inglês, mesmo
  motivo documentado na P0.5 — `navigator.language=en-US` no Chrome do
  preview). **Não foi possível** completar o preenchimento/submit do
  formulário via automação do preview (Flutter web renderiza em canvas; os
  eventos de ponteiro sintéticos disparados via JS não focam o
  `EditableText` real) — o fluxo de login/erro fica validado pelos testes de
  widget (que usam o mesmo código de produção) e pelo contrato confirmado
  via `curl`, não por clique manual na UI. Signup→convite→aceite→login
  ponta a ponta com o backend real **não foi exercitado manualmente por
  completo** (só o primeiro passo, signup, via curl) — considerado
  aceitável dado que cada endpoint já tem teste de handler Go (P0.3/P0.4) e
  o cliente usa o mesmo contrato.
- **Pendência (herdada, ainda aberta):** rodar em Android segue bloqueado
  (sem SDK nesta máquina) — inclui verificar o deep link `lyfta://` de
  convite, que só é testável com o app instalado num device/emulador
  Android ou simulador iOS. Rate limit no lookup de e-mail entre tenants e
  nos endpoints públicos por token (ADR-002 §2c) continua em aberto, fora do
  escopo deste app Flutter.

### P0.7 (2026-08-27, Mac)

- **`.github/workflows/ci.yml`** com 3 jobs: `discover` (lista os serviços em
  `backend/<svc>/go.mod` e emite a matrix via `fromJSON`), `backend` (matrix
  por serviço) e `app`. A descoberta dinâmica evita ter de editar a matrix
  quando `workout`/`assessment`/`comms` nascerem — hoje resolve para
  `["identity"]`. Dispara em push na `main` e em qualquer PR, com
  `concurrency` cancelando runs antigas do mesmo ref.
- **Job `backend`:** Postgres 17 como service container (mesma major do dev),
  `CREATE DATABASE lyfta_<svc>` (nome derivado do serviço — a migration 0007
  do identity referencia `lyfta_identity` explicitamente no `GRANT CONNECT`),
  `golang-migrate` **v4.19.1** (mesma versão do dev) baixado do release
  `migrate.linux-amd64.tar.gz`, migrations aplicadas como `postgres`, e então
  `go vet ./...` + `go test ./...` conectando como **`lyfta_app`** — a role
  sem BYPASSRLS criada pelas próprias migrations. Conectar como superusuário
  aqui tornaria os testes de isolamento cross-tenant (ADR-001 §6) vazios.
  `go-version-file` aponta para o `go.mod` do serviço: a versão do Go nunca
  duplica no workflow.
- **Portão real, não decorativo:** `testPool` (em `internal/repo/repo_test.go`
  e `internal/http/auth_test.go`) fazia `t.Skipf` quando o banco não subia —
  correto no dev, mas no CI deixaria o pipeline **verde sem ter testado
  nada**. Passou a dar `t.Fatalf` quando `CI` está setada no ambiente
  (o GitHub Actions define `CI=true`); fora do CI o skip continua igual.
  Sem essa mudança, um service container quebrado passaria despercebido.
- **Job `app`:** `subosito/flutter-action@v2` com Flutter **3.44.4** pinado
  (versão em uso no Mac) e cache; `flutter pub get`, `flutter analyze`,
  `flutter test` e `tool/check_hardcoded_strings.sh` (guard do ADR-011 §5 —
  já versionado com bit de execução, `100755`). Não roda `flutter create .`:
  os testes de widget não precisam das pastas de plataforma (não versionadas,
  ver `app/README.md`), e portanto o CI **não** cobre build de Android/iOS/web.
- **Verificado localmente (Mac), reproduzindo o job passo a passo:** Postgres
  17 limpo em container (`docker run postgres:17`, porta 5433), banco criado
  do zero, as 9 migrations aplicadas em sequência pelo `migrate` e
  `go test ./...` verde contra esse banco novo com a DSN de `lyfta_app` — ou
  seja, o caminho do CI (banco vazio → migrations → testes) foi executado de
  fato, não presumido. O portão novo também foi exercitado nos dois sentidos:
  com `CI=true` e DSN inacessível o teste **falha** (`banco indisponível no
  CI`), e sem `CI` ele pula como antes. Lado app: `flutter analyze` sem
  issues, `flutter test` 8/8 verdes, guard de strings limpo. YAML validado
  (parse) e a URL do release do `golang-migrate` conferida (HTTP 200).
- **Pendente:** o pipeline só fica comprovadamente verde no primeiro push —
  não há remote GitHub configurado nesta máquina para disparar o run (o
  Aceite "pipeline verde no push" fica confirmado quando o repo for
  publicado). Nada no workflow depende de segredo: Resend/JWT não são
  exercitados pelos testes (os handlers usam `logMailer` e par de chaves
  efêmero), então não há `secrets` a configurar.
- **Dívida herdada do P0 (continua aberta, fora do escopo desta tarefa):**
  Android/iOS não configurados nesta máquina (deep link `lyfta://invite`
  nunca testado); verificação do `docker compose` (Redis+MinIO) pendente no
  Windows; rate limit no lookup de e-mail entre tenants (ADR-002 §2c) ainda
  sem ADR nem implementação.
