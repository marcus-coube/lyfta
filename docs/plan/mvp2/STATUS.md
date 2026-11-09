# STATUS — MVP 2.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** P5.3 — anamnese: objetivo, lesões e restrições (assessment).

| Fase | Progresso | Situação |
|---|---|---|
| P5 — Alunos | 2/5 | em andamento |
| P6 — Builder | 0/5 | não iniciada |
| P7 — Financeiro | 0/5 | não iniciada |
| P8 — Dashboard e release | 0/4 | não iniciada |
| **Total** | **2/19** | |

## Bancos locais

| Banco | Criado (Windows) | Criado (Mac) |
|---|---|---|
| lyfta_billing (P7.1) | ⬜ | ⬜ |

Os quatro bancos do 1.0 seguem na tabela do [STATUS do 1.0](../mvp1/STATUS.md).

## Fora do 2.0 (decidido)

| Item | Decisão |
|---|---|
| PIX, cartão, Asaas/Stripe, webhooks | Adiado — ADR-017 §2. O schema já comporta (`provider`, `payment_provider_events`) |
| Cobrança automática, lembrete de vencimento (push/e-mail) | Adiado com o PIX |
| Pagamento parcial, multa/juros, desconto | Adiado; no 2.0 a baixa quita a fatura inteira |
| Recibo/nota fiscal | Adiado |

## Log de marcos

| Data | Evento |
|---|---|
| 2026-11-08 | Plano do 2.0 criado (18 tarefas, P5–P8); ADR-017 (serviço `billing`, só baixa manual) e ADR-018 (modelos por cópia) |
| 2026-11-08 | Revisão do usuário: acesso do coach ao financeiro vira configuração da organização; exclusão de conta bloqueada com fatura pendente e titular retido no financeiro (ADR-017 §3/§5, substitui ADR-008 §2 nesse ponto). P7.5 nova; total 19 |
| 2026-11-08 | **P5.1 concluída:** `tenants.timezone` + `coach_billing_access` (migration 0013), `GET/PUT /v1/tenant`, M2M de tenants, claim `tz` no JWT, job de pendente do comms por fuso do tenant (`NOTIFICATION_TIMEZONE` removida), seção Organização na Conta do owner |
| 2026-11-09 | **P5.2 concluída:** migration `0014_student_registry` (telefone, nascimento, status `inactive`, `user_status_events`), `/v1/students` (lista com cursor, ficha, edição, inativar/reativar, histórico), `GET/PATCH /v1/me`, M2M `GET /internal/v1/students/{id}` e job de pendente do comms ignorando inativos |
