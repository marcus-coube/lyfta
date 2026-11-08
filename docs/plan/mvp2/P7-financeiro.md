# P7 — Financeiro (baixa manual)

Meta da fase: o owner cadastra planos de mensalidade, vincula alunos, o sistema
gera as faturas do mês e marca as vencidas; o owner (e o coach, se a
organização liberar — ADR-017 §3) dá baixa manual; só o owner estorna. Aluno
com fatura pendente não exclui a conta (ADR-017 §5).
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
   - `billing_customers` (`student_id` PK com tenant, `name`, `email`,
     `account_deleted_at NULL`, `updated_at`): titular retido do ADR-017 §5;
     preenchido por M2M ao `identity` (`GET /internal/v1/students/{id}`, P5.2)
     quando a assinatura é criada e atualizado a cada nova assinatura;
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

**Objetivo:** operações do owner, do coach conforme a configuração da
organização, e leitura do aluno.
**Passos:**
0. Cliente `tenantsettings` (cache de 30 s, M2M `GET /internal/v1/tenants/{id}`
   da P5.1; `identity` fora = 500, como o `coachlink`). Matriz de acesso:

   | Rota | owner | coach `own_students` | coach `status_only` |
   |---|---|---|---|
   | planos de mensalidade | ✓ | leitura (para assinar) | ✗ |
   | assinaturas e faturas | todos | só alunos do vínculo | ✗ |
   | baixa manual | ✓ | só alunos do vínculo | ✗ |
   | estorno, cancelar fatura, `summary` | ✓ | ✗ | ✗ |
   | status derivado | ✓ | ✓ | ✓ |

   Aluno fora do vínculo = 404 `student_not_found`; rota negada pelo modo = 403
   `billing_access_denied`.
1. Rotas (owner, e coach conforme a matriz):
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
2. Status: `GET /v1/billing/students/status?ids=` → `{id: ok|delinquent|none}`
   (coach: só alunos do vínculo, ADR-016), **sem valores**. Todo coach e owner.
3. Listas e detalhes devolvem `customer` (`name`, `email`, `account_deleted`)
   vindo de `billing_customers`, para a conta excluída continuar legível.
4. Aluno: `GET /v1/me/invoices` (somente leitura, sem `note` interna).
5. Status derivado (ADR-007 §3): `delinquent` ⇔ existe fatura `overdue`;
   nenhuma coluna de status financeiro do aluno.
**Aceite:** baixa e estorno idempotentes e auditáveis (nada é apagado); teste
da matriz de acesso nos dois modos (trocar o modo vale em até 30 s); testes de handler (feliz + fatura já paga
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
1. `features/billing/`, aba **Financeiro** no shell do owner (e do coach com
   `own_students`, filtrada aos alunos dele, sem estorno nem receita):
   - Faturas: filtros (em aberto, vencidas, pagas, canceladas; mês), lista
     (tabela no desktop) com aluno, vencimento, valor, status; ação "dar baixa"
     (data, observação; confirmação) e "estornar" (com motivo);
   - Planos de mensalidade: CRUD e arquivar.
2. Ficha do aluno ganha a aba **Financeiro** (owner, e coach com
   `own_students`): assinatura (criar com
   plano, valor, dia de vencimento; editar; pausar; cancelar) e histórico de
   faturas e pagamentos.
3. Selo "inadimplente" na lista de alunos e na ficha (coach e owner, pela rota
   de status da P7.2). Fatura de conta excluída mostra nome, e-mail e o selo
   "conta excluída".
4. Toggle na seção Organização (P5.1): "Professores gerenciam o financeiro dos
   próprios alunos" (`coach_billing_access`), com texto do que cada modo libera. Ao inativar aluno com assinatura ativa, aviso com atalho
   para cancelar.
5. Aluno: "Minhas mensalidades" na Conta (lista read-only com status).
6. Dinheiro: `int` de centavos de ponta a ponta; campo de valor com máscara
   que converte texto → centavos sem `double`; exibição com
   `NumberFormat.currency` no locale da tela.
**Aceite:** owner cria plano, assina um aluno, a fatura aparece, dá baixa,
estorna e ela volta a vencida; com o toggle desligado o coach não vê a aba
nem valores, ligado vê só os alunos dele e sem estorno;
testes de widget do campo de valor (pt-BR `1.234,56` e en `1,234.56` →
`123456`) e da lista de faturas. Strings nos 3 idiomas.

## - [ ] P7.5 Exclusão de conta com financeiro (identity, billing, Flutter)

**Objetivo:** ADR-017 §5 — quem deve não sai; quem sai continua legível no
financeiro.
**Passos:**
1. billing: `GET /internal/v1/users/{id}/pending` → `{pending: bool,
   open_invoices, overdue_invoices}`; `DELETE /internal/v1/users/{id}`
   idempotente: cancela a assinatura ativa e as faturas `open` **futuras**
   (vencimento depois de hoje no fuso do tenant), recebe `{name, email}` no corpo
   e grava em `billing_customers` com `account_deleted_at`. Faturas e
   pagamentos ficam intactos.
2. identity: `DELETE /v1/me` chama o `pending` **antes** de marcar `deleting`;
   pendência = 409 `pending_invoices` com a contagem em `params`, nada muda.
   Depois inclui o `billing` na orquestração da P4.5 (antes de anonimizar o
   usuário, passando nome e e-mail). `billing` fora do ar = 502 repetível, como
   os outros serviços.
3. App: o erro `pending_invoices` vira mensagem explicando que é preciso quitar
   as mensalidades com a organização, com atalho para "Minhas mensalidades".
4. Termos (`app/assets/legal/`): a política passa a dizer que os registros
   financeiros guardam nome e e-mail após a exclusão. `TERMS_VERSION` sobe e o
   gate da P4.5 pede novo aceite. O texto entra na revisão jurídica (L6).
**Aceite:** aluno com fatura vencida recebe 409 e a conta fica intacta;
aluno quitado exclui, some do app e do login, e a fatura paga dele continua
mostrando nome, e-mail e o selo "conta excluída" ao owner; teste de handler no
identity (pendente + billing fora do ar) e no billing (idempotência do DELETE).

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
