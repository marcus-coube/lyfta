# STATUS — MVP 1.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P0.7` (CI)

| Fase | Progresso | Situação |
|---|---|---|
| P0 — Fundação | 6/7 | em andamento |
| P1 — Treino | 0/8 | não iniciada |
| P2 — Evolução | 0/5 | não iniciada |
| P3 — Comunicação | 0/5 | não iniciada |
| P4 — Praticidade | 0/4 | não iniciada |
| **Total** | **6/29** | |

## Bancos locais

| Banco | Criado (Windows) | Criado (Mac) |
|---|---|---|
| lyfta_identity | ✅ | ✅ |
| lyfta_workout | ✅ | ✅ |
| lyfta_assessment | ✅ | ✅ |
| lyfta_comms | ✅ | ✅ |

Criar em cada máquina: `psql -U postgres -f backend/scripts/create-dbs.sql`
(idempotente).

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
