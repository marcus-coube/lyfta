# P7 — Financeiro (baixa manual)

Meta da fase: o owner cadastra planos de mensalidade, vincula alunos, o sistema
gera as faturas do mês e marca as vencidas; o owner dá baixa manual e estorna.
**Sem PIX** (ADR-017 §2): nenhum provider, webhook ou cobrança automática.

Refs normativas: ADR-001, ADR-007, ADR-008 §2, ADR-013, ADR-016, ADR-017.
Depende de: P5.1 (fuso do tenant), P5.2 (status do aluno).

---

## - [ ] P7.1 Serviço `billing`: bootstrap e schema (Go)

**Objetivo:** sexto serviço (8085, `lyfta_billing`) com o modelo inteiro do ADR-007.
**Passos:**
1. Bootstrap idêntico ao `assessment` (chi + pgxpool + slog, `security`, `repo`,
   `coachlink`, Sentry, Recover — duplicados, ADR-013 §2), `/healthz`,
   `/v1/whoami`. Linha nova em `backend/README.md` (serviços + bancos),
   `create-dbs.sql`, `.env.example`, launch configs.
2. Migrations (todas com `tenant_id` + RLS forçada + índice por `tenant_id`):
   - `billing_plans` (nome, `amount_cents BIGINT > 0`, `currency CHAR(3)
     DEFAULT 'BRL'`, `active`, timestamps);
   - `subscriptions` (`student_id`, `billing_plan_id`, `amount_cents` congelado
     na adesão, `due_day` 1–28, `starts_on DATE`, `status
     active|paused|canceled`, `canceled_at`; **uma ativa por aluno** via índice
     único parcial);
   - `invoices` (`subscription_id`, `student_id`, `period CHAR(7)` `YYYY-MM`,
     `due_date`, `amount_cents`, `status open|paid|overdue|canceled`,
     `paid_at`; unique `(subscription_id, period)`; trigger: fatura `paid` é
     imutável salvo transição para `open|overdue` via estorno);
   - `payments` (`invoice_id`, `amount_cents`, `method manual|pix|card`,
     `provider`, `provider_ref`, `paid_at`, `recorded_by`, `note`,
     `reversed_by UUID NULL`, `reversal_of UUID NULL`; append-only);
   - `payment_provider_events` (crus, vazia no 2.0 — ADR-007 §4).
3. Nenhuma coluna de dinheiro é `NUMERIC`/float (teste que varre o
   `information_schema`).
**Aceite:** CI descobre o serviço sozinho e roda as migrations; teste de
isolamento cross-tenant; teste do trigger de imutabilidade da fatura paga.

## - [ ] P7.2 API do financeiro (billing)

**Objetivo:** operações do owner e leituras do coach e do aluno.
**Passos:**
1. Owner (`RequireRole(owner)`):
   - `GET/POST/PUT /v1/billing/plans`, `POST .../{id}/archive`;
   - `POST /v1/billing/subscriptions` `{student_id, billing_plan_id,
     amount_cents?, due_day, starts_on}` (gera já a fatura do período corrente
     se `starts_on` cair nele); `PATCH .../{id}` (valor e vencimento valem a
     partir da **próxima** fatura), `POST .../{id}/pause|resume|cancel`
     (cancelar cancela faturas `open` futuras, nunca as vencidas);
   - `GET /v1/billing/invoices?status=&period=&student_id=&cursor=`,
     `POST /v1/billing/invoices/{id}/cancel`;
   - `POST /v1/billing/invoices/{id}/payments` `{paid_at, note}`: baixa manual,
     sempre pelo valor integral da fatura (`method=manual`); fatura vira `paid`.
     Idempotente por header `Idempotency-Key` (doc 008);
   - `POST /v1/billing/payments/{id}/reverse` `{note}`: grava pagamento de
     estorno (`reversal_of`), marca `reversed_by` no original e devolve a fatura
     para `open` ou `overdue` conforme a data no fuso do tenant.
2. Coach: `GET /v1/billing/students/status?ids=` → `{id: ok|delinquent|none}`
   só dos alunos do vínculo (ADR-016), **sem valores**. Owner usa a mesma rota.
3. Aluno: `GET /v1/me/invoices` (somente leitura, sem `note` interna).
4. Status derivado (ADR-007 §3): `delinquent` ⇔ existe fatura `overdue`;
   nenhuma coluna de status financeiro do aluno.
**Aceite:** baixa e estorno idempotentes e auditáveis (nada é apagado); coach
recebe 403 em qualquer rota de valor; testes de handler (feliz + fatura já paga
= 409 `invoice_already_paid` + estorno duplo = 409 `payment_already_reversed`).

## - [ ] P7.3 Jobs: geração mensal e vencimento (billing)

**Objetivo:** faturas nascem e vencem sozinhas, no fuso de cada tenant.
**Passos:**
1. Goroutine com tick de 15 min no `billing`; a cada tick pega
   `pg_try_advisory_lock` (uma instância por vez) e varre os tenants pela M2M da
   P5.1 (cache de 10 min).
2. **Geração:** para cada assinatura `active`, garante a fatura do período
   corrente no fuso do tenant (`INSERT ... ON CONFLICT DO NOTHING` no unique
   `(subscription_id, period)`); `due_date` = `due_day` do mês. Assinatura
   `paused` não gera.
3. **Vencimento:** fatura `open` com `due_date` < hoje (fuso do tenant) vira
   `overdue`.
4. Relógio injetável (`Clock`) para teste; job idempotente (rodar 2× no mesmo
   dia não duplica nada).
5. Aluno inativado (P5.2) **não** cancela a assinatura sozinho: o app avisa o
   owner ao inativar aluno com assinatura ativa (P7.4).
**Aceite:** teste com relógio fake atravessando a virada do mês em dois fusos
(São Paulo e Lisboa) gera uma fatura por assinatura e vence no dia certo de
cada tenant; duas instâncias simultâneas não duplicam (teste do lock).

## - [ ] P7.4 App — financeiro do owner e faturas do aluno (Flutter)

**Objetivo:** o owner opera o financeiro sem planilha.
**Passos:**
1. `features/billing/`, aba **Financeiro** só no shell do owner:
   - Faturas: filtros (em aberto, vencidas, pagas, canceladas; mês), lista
     (tabela no desktop) com aluno, vencimento, valor, status; ação "dar baixa"
     (data, observação; confirmação) e "estornar" (com motivo);
   - Planos de mensalidade: CRUD e arquivar.
2. Ficha do aluno ganha a aba **Financeiro** (owner): assinatura (criar com
   plano, valor, dia de vencimento; editar; pausar; cancelar) e histórico de
   faturas e pagamentos.
3. Selo "inadimplente" na lista de alunos e na ficha (coach e owner, pela rota
   de status da P7.2). Ao inativar aluno com assinatura ativa, aviso com atalho
   para cancelar.
4. Aluno: "Minhas mensalidades" na Conta (lista read-only com status).
5. Dinheiro: `int` de centavos de ponta a ponta; campo de valor com máscara
   que converte texto → centavos sem `double`; exibição com
   `NumberFormat.currency` no locale da tela.
**Aceite:** owner cria plano, assina um aluno, a fatura aparece, dá baixa,
estorna e ela volta a vencida; coach não vê a aba Financeiro nem valores;
testes de widget do campo de valor (pt-BR `1.234,56` e en `1,234.56` →
`123456`) e da lista de faturas. Strings nos 3 idiomas.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
