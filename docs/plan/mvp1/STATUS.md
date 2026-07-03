# STATUS — MVP 1.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P0.1` (infra local e compose)

| Fase | Progresso | Situação |
|---|---|---|
| P0 — Fundação | 0/7 | não iniciada |
| P1 — Treino | 0/8 | não iniciada |
| P2 — Evolução | 0/5 | não iniciada |
| P3 — Comunicação | 0/5 | não iniciada |
| P4 — Praticidade | 0/4 | não iniciada |
| **Total** | **0/29** | |

## Bancos locais

| Banco | Criado (Windows) | Criado (Mac) |
|---|---|---|
| lyfta_identity | ✅ | ⬜ |
| lyfta_workout | ✅ | ⬜ |
| lyfta_assessment | ✅ | ⬜ |
| lyfta_comms | ✅ | ⬜ |

Criar em cada máquina: `psql -U postgres -f backend/scripts/create-dbs.sql`
(idempotente).

## Log de marcos

| Data | Evento |
|---|---|
| 2026-07-03 | Plano criado (29 tarefas, P0–P4); agente mvp-dev criado |
| 2026-07-03 | Bancos criados no Postgres local (Windows) |
