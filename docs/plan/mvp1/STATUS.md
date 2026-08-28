# STATUS — MVP 1.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P1.4` (workout — API do builder e atribuição)

| Fase | Progresso | Situação |
|---|---|---|
| P0 — Fundação | 7/7 | concluída |
| P1 — Treino | 3/8 | em andamento |
| P2 — Evolução | 0/5 | não iniciada |
| P3 — Comunicação | 0/5 | não iniciada |
| P4 — Praticidade | 0/4 | não iniciada |
| **Total** | **10/29** | |

## Bancos locais

| Banco | Criado (Windows) | Criado (Mac) |
|---|---|---|
| lyfta_identity | ✅ | ✅ |
| lyfta_workout | ✅ | ✅ |
| lyfta_assessment | ✅ | ✅ |
| lyfta_comms | ✅ | ✅ |

Criar em cada máquina: `psql -U postgres -f backend/scripts/create-dbs.sql`
(idempotente).

## Seed por máquina

| Seed | Windows | Mac |
|---|---|---|
| biblioteca global de exercícios (P1.3) | ⬜ | ✅ |

Aplicar em cada máquina, depois das migrations do workout (idempotente,
exige superusuário — exercício global é `tenant_id NULL`):
`psql -U postgres -d lyfta_workout -f backend/workout/seed/exercises_seed.sql`

## Log de marcos

| Data | Evento |
|---|---|
| 2026-07-03 | Plano criado (29 tarefas, P0–P4); agente mvp-dev criado |
| 2026-07-03 | Bancos criados no Postgres local (Windows) |
| 2026-07-03 | P0.1 concluída: compose (Redis+MinIO) e .env.example — Docker não disponível nesta máquina, verificação pendente (ver Notas de execução em P0-fundacao.md) |
| 2026-07-03 | P0.2 concluída (Mac): identity — esqueleto Go (chi+pgxpool+slog), 7 migrations (tenants/users/user_roles/refresh_tokens/invitations/password_resets/app_role), RLS forçada + role `lyfta_app` sem BYPASSRLS, `/healthz`, teste de isolamento cross-tenant. Go e golang-migrate instalados via brew nesta sessão (ver Notas de execução em P0-fundacao.md) |
| 2026-07-03 | P0.3 concluída (Mac): identity — signup/login/refresh/logout, JWT EdDSA (golang-jwt/v5), senha argon2id, migration 0008 com função `find_tenants_by_email` (SECURITY DEFINER, superfície mínima) para resolver login entre tenants sob RLS forçada, `backend/scripts/gen-keys.sh`. Testes de handler cobrindo todo o Aceite (ver Notas de execução em P0-fundacao.md) |
| 2026-07-04 | P0.4 concluída (Mac): identity — convites (Resend/`logMailer`) e recuperação de senha; primeiro endpoint autenticado (middleware `RequireAuth`+`RequireRole`), migration 0009 (`find_invitation_by_token`/`find_password_reset_by_token`, SECURITY DEFINER). 5 testes de handler novos cobrindo o Aceite. Agente `mvp-dev` travou 2× no meio da tarefa; finalizada manualmente na sessão principal (ver Notas de execução em P0-fundacao.md) |
| 2026-07-04 | P0.5 concluída (Mac): app — núcleo Flutter (Riverpod, go_router, Dio com interceptors de auth/refresh e mapeamento de erro, i18n ADR-011 com fallback pt-PT→pt-BR automático, guard `check_hardcoded_strings`), telas placeholder (forgot/invite/shells coach+student) e login migrado para ARB. Flutter instalado via brew nesta sessão (Mac); Android SDK/Xcode não configurados — rodar em Android fica pendente (ver Notas de execução em P0-fundacao.md) |
| 2026-07-12 | P0.6 concluída (Mac): app — auth real ponta a ponta ligada ao `identity` (`AuthRepository`, `AuthController` com sessão persistida e refresh automático no boot), telas de signup/login/aceitar convite/esqueci-redefinir senha funcionais com erro i18n, bottom sheet de `multiple_tenants`, shells responsivos (`NavigationRail` web/desktop >= 840px, `NavigationBar` mobile). Teste de widget de login (feliz + erro de credencial) sobre HTTP fake; contrato validado também via `curl` contra o `identity` real. `flutter analyze`/`flutter test`/guard de strings limpos. Android e o deep link `lyfta://` de convite seguem pendentes (sem SDK nesta máquina); fluxo completo signup→convite→aceite→login não exercitado manualmente ponta a ponta na UI (ver Notas de execução em P0-fundacao.md) |
| 2026-08-27 | P0.7 concluída (Mac): CI no GitHub Actions — job `backend` (matrix descoberta a partir de `backend/<svc>/go.mod`, Postgres 17 em service container, migrations via golang-migrate v4.19.1, `go vet`+`go test` conectando como `lyfta_app`) e job `app` (`flutter analyze`/`test` + guard de strings, Flutter 3.44.4 pinado). `testPool` passou a falhar em vez de pular quando `CI` está setada — sem isso o pipeline ficaria verde sem banco. Fluxo do job reproduzido localmente com Postgres 17 limpo em Docker; **P0 fechada** (ver Notas de execução em P0-fundacao.md) |
| 2026-08-27 | P1.1 concluída (Mac): serviço `workout` (8082, banco `lyfta_workout`) — bootstrap chi+pgxpool+slog só com validação de JWT (chave pública do identity), 13 migrations com o modelo inteiro do ADR-004 (biblioteca com policy dupla global/tenant, plano→versão→dia→bloco→exercício→sets estruturados, rotação, sessões e logs) e imutabilidade garantida por trigger: versão publicada não muda e log de série é append-only. 8 testes verdes; integração identity→workout confirmada com token real (ver Notas de execução em P1-treino.md) |
| 2026-08-27 | P1.2 concluída (Mac): workout — `POST /v1/media/presign` (owner|coach) assinando PUT no S3-compatible com `aws-sdk-go-v2` (dependência nova aprovada; escolhida por ser a que a Cloudflare documenta para R2). Content-Type e Content-Length entram na assinatura, então o teto de 50 MB é garantia do storage; chave por tenant vinda da claim; `S3_PUBLIC_BASE_URL` alterna entre GET assinado e URL pública de CDN. Upload real no MinIO verificado por teste e via curl ponta a ponta; CI ganhou MinIO no job do workout (ver Notas de execução em P1-treino.md) |
| 2026-08-27 | P1.3 concluída (Mac): workout — API da biblioteca (`GET /v1/exercises` com busca sem acento, filtros da taxonomia, cursor keyset e fallback de locale resolvido no banco; `GET/POST/PUT /v1/exercises/{id}`), taxonomia como código estável (o app traduz, ADR-011 §5), `media_url` validada contra a pasta do tenant e re-assinada na leitura, e seed de 41 exercícios globais em 3 locales (`seed/exercises_seed.sql`, idempotente, superusuário, aplicado também no CI). Global é somente leitura: `PUT` responde `403 exercise_is_global`. 26 testes verdes e smoke manual com token real de coach `pt-PT` (ver Notas de execução em P1-treino.md) |
