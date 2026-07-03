# P0 — Fundação (infra, identity, Flutter conectado)

Meta da fase: um professor cria a conta da academia, convida um aluno por e-mail
(Resend), o aluno define a senha e ambos logam no app (mobile e web) caindo em
shells distintos por papel. Backend `identity` completo; demais serviços ainda não.

Refs normativas: ADR-001, ADR-002, ADR-011, ADR-013, `backend/README.md`.

---

## - [ ] P0.1 Infra local e compose

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

## - [ ] P0.2 Serviço identity — esqueleto + migrations

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

## - [ ] P0.3 identity — signup, login, refresh, JWT

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
