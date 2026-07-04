# STATUS — MVP 1.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P0.4` (identity — convites via Resend e recuperação de senha)

| Fase | Progresso | Situação |
|---|---|---|
| P0 — Fundação | 3/7 | em andamento |
| P1 — Treino | 0/8 | não iniciada |
| P2 — Evolução | 0/5 | não iniciada |
| P3 — Comunicação | 0/5 | não iniciada |
| P4 — Praticidade | 0/4 | não iniciada |
| **Total** | **3/29** | |

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
