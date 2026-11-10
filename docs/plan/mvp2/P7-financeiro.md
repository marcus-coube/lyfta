# P7 — Financeiro (baixa manual)

Meta da fase: o owner cadastra planos de mensalidade, vincula alunos, o sistema
gera as faturas do mês e marca as vencidas; o owner (e o coach, se a
organização liberar — ADR-017 §3) dá baixa manual; só o owner estorna. Aluno
com fatura pendente não exclui a conta (ADR-017 §5).
**Sem PIX** (ADR-017 §2): nenhum provider, webhook ou cobrança automática.

Refs normativas: ADR-001, ADR-007, ADR-008 §2, ADR-013, ADR-016, ADR-017.
Depende de: P5.1 (fuso do tenant), P5.2 (status do aluno).

---

## - [x] P7.1 Serviço `billing`: bootstrap e schema (Go)

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

## - [x] P7.2 API do financeiro (billing)

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

## - [x] P7.3 Jobs: geração mensal e vencimento (billing)

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

## - [x] P7.4 App — financeiro do owner e faturas do aluno (Flutter)

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

**P7.1 (Mac, 2026-11-10)**
- Bootstrap duplicado do `assessment` (`security`, `obs`, `coachlink`, `repo`
  com `WithTenant`, middlewares, Sentry/Recover). Sem S3 nem `consent`: o
  financeiro não tem mídia nem finalidade de consentimento (o campo `Consents`
  do JWT fica só por paridade). Rotas: `/healthz` e `/v1/whoami`; o
  `coachlink` já vem no pacote, sem ser ligado ao router (a API é a P7.2).
- Migrations 0001–0004 (up/down/up verificado): customers+plans, subscriptions
  +invoices (trigger de fatura paga imutável), payments (trigger append-only)
  +`payment_provider_events`, role `lyfta_app`. RLS forçada, `tenant_id` e
  `UNIQUE (tenant_id, id)` nas tabelas pai; FKs compostas `(tenant_id, id)`
  entre tabelas filhas garantem pai do mesmo tenant.
- `billing_customers` tem PK `(tenant_id, student_id)` e a assinatura tem FK
  para ele: criar assinatura **exige** o customer já gravado (P7.2 grava a cópia
  do identity antes, na mesma transação).
- Desvio pequeno: o índice único parcial de assinatura vale para
  `status IN ('active','paused')`, não só `active` — assim retomar uma pausada
  nunca colide com assinatura nova criada durante a pausa. Se a P7.2 preferir
  o literal, é trocar o predicado do índice.
- Trigger da fatura paga: só sai de `paid` para `open|overdue` com `paid_at`
  NULL e demais campos iguais (o estorno); `DELETE` de paga é bloqueado. O
  CHECK `(status='paid') = (paid_at IS NOT NULL)` obriga a P7.2 a setar os dois
  juntos. `payments`: único UPDATE permitido é preencher `reversed_by`; o
  estorno é um payment novo com `reversal_of`.
- Dívida: `billing/.env` local não foi criado pelo agente (precisa da
  `JWT_PUBLIC_KEY` do identity): copiar `.env.example` e colar a pública antes
  de subir o serviço pela launch config `billing`. O CI não precisa: descobre o
  serviço por `backend/billing/go.mod`, cria `lyfta_billing` e roda as migrations.

**P7.2 (Mac, 2026-11-10)**
- Rotas sob `/v1/billing` (matriz por middleware: `requireOwner`,
  `requireOperator` = owner ou coach `own_students`, `requireStaff` só para
  `students/status`) + `GET /v1/me/invoices`. Vínculo do coach por recurso
  (`checkStudentLink`, 404 `student_not_found`); nas listas o coach recebe só
  os alunos do vínculo. Rota negada = 403 `billing_access_denied` (inclui
  aluno e coach nas rotas só do owner). Modo do coach e fuso vêm do novo
  pacote `tenantsettings` (cache 30 s, `TENANT_SETTINGS_CACHE_TTL`; identity
  fora = 500, owner não depende dele nas listas). Teste de TTL com relógio
  fake; teste de matriz troca o modo com TTL 0.
- **identity (M2M novo):** `GET /internal/v1/students/{id}?tenant_id=` →
  `{id, name, email, status}` (a assinatura precisa copiar nome e e-mail para
  `billing_customers`, ADR-017 §5). Cliente `studentdir` no billing; sem
  cache. Teste no `TestStudentLifecycle` do identity.
- **Migration 0005 (desvio pequeno):** `payments.idempotency_key` + índice
  único parcial `(tenant_id, idempotency_key)`. O schema da P7.1 não tinha
  onde guardar a chave e `provider_ref` não serve (CHECK `manual` => provider
  NULL e índice com provider NULL não deduplica). Replay na mesma fatura =
  200 com o mesmo pagamento; mesma chave em outra fatura = 409
  `idempotency_key_conflict`; sem chave, fatura paga = 409
  `invoice_already_paid`. Fatura travada com `FOR UPDATE` (teste de baixa
  concorrente: 1x201 + 1x409).
- Decisões: (a) fatura do mês de início: `due_date` = `due_day` do mês, mas
  **nunca antes de `starts_on`** (`repo.DueDateFor`), e nasce `overdue` só se
  esse vencimento já passou no fuso do tenant. **P7.3 deve usar a mesma
  regra e não gerar período anterior ao mês de `starts_on`.** (b) cancelar
  assinatura cancela faturas `open` com vencimento **depois de hoje** (fuso
  do tenant), igual ao que a P7.5 vai usar na exclusão. (c) `paid_at` da
  baixa é opcional (vazio = agora), aceita RFC 3339 ou `AAAA-MM-DD`
  (meio-dia local, limitado a agora); futuro = 400. Valor da baixa sempre o
  integral da fatura. (d) estorno exige `note` (motivo); estorno de
  estorno = 409 `payment_is_reversal`. (e) `students/status` devolve o mapa
  puro `{id: ok|delinquent|none}`; `ok` = tem assinatura (qualquer estado),
  `none` = nunca teve; ids fora do vínculo do coach são omitidos. (f) Extras
  além dos passos, que o app da P7.4 vai precisar: `GET /subscriptions`
  (`student_id`, `status`), `GET /subscriptions/{id}`, `GET /invoices/{id}`
  (com histórico de pagamentos e estornos). (g) `/me/invoices` devolve só
  id, período, vencimento, valor, status e `paid_at` (sem `note`, titular ou
  pagamentos). (h) Erros de estado de assinatura: 409
  `invalid_subscription_state` com `status` em `params`.
- Fora desta tarefa: `GET /v1/billing/summary` (P8.x, owner-only como na
  matriz); `account_deleted` já sai do `customer` mas só a P7.5 o liga.
- Pendência do usuário (da P7.1, ainda vale): `billing/.env` precisa de
  `IDENTITY_URL` (default `http://localhost:8081`) e `INTERNAL_TOKEN` igual ao
  do identity para as rotas que consultam o identity funcionarem no dev.

**P7.3 (Mac, 2026-11-10)**
- Job em `billing/internal/job` (`MonthlyJob`), tick de 15 min + varredura na
  subida, iniciado no `main`. Cada tick segura `pg_try_advisory_lock` numa
  conexão dedicada do pool (lock de sessão; se o unlock falhar a conexão é
  descartada) e, não conseguindo, volta sem fazer nada. Lista de tenants pelo
  novo `internal/tenantclient` (cópia do `comms`, M2M `GET /internal/v1/tenants`,
  cache de 10 min). `Clock` = `WithClock` (mesmo padrão do job do comms).
- Operações em `repo.JobRepo`, uma transação por tenant (RLS):
  `GenerateInvoices` (assinaturas `active` com mês de `starts_on` <= mês
  corrente; vencimento por `repo.DueDateFor`; `ON CONFLICT (subscription_id,
  period) DO NOTHING`, então também convive com a fatura criada junto da
  assinatura) e `MarkOverdue` (`open` com `due_date` < hoje local; só `open`).
  Hoje = data civil no fuso do tenant. Falha em um tenant é logada e não
  impede os demais.
- Decisões: gera só o período **corrente** — assinatura retomada de pausa ou
  serviço parado vários meses não gera retroativo (baixa/ajuste manual é fora
  do 2.0). A fatura nasce `open` e a mesma varredura a vence se já passou
  (equivale à regra da P7.2). Faturas de assinatura pausada/cancelada que já
  existiam como `open` continuam vencendo normalmente (a cancelada com
  vencimento futuro já foi cancelada pela P7.2). Sem migration.
- Testes (banco real, nenhum skip): virada de mês SP × Lisboa no mesmo
  instante (uma fatura por assinatura, pausada/cancelada/futura não geram,
  rodar 2x não duplica, vence no dia local certo), fronteira de vencimento
  entre fusos, nada antes do mês de `starts_on`, só `open` vira `overdue`, e
  lock (tick com o lock tomado não roda; 4 ticks concorrentes = 1 fatura).

**P7.4 (Mac, 2026-11-10)**
- `features/billing/` (domain, data, presentation) + `shared/money/money.dart`
  (`formatCents`, `maskCents`, `parseCents`, `MoneyInputFormatter`) e
  `shared/widgets/ly_money_field.dart`. Dinheiro é `int` de centavos de ponta a
  ponta: o campo lê só os dígitos (os dois últimos são os centavos) e monta o
  texto com `NumberFormat.decimalPattern` sobre inteiros, sem `double`. A única
  conversão para fracionário é a exibição (`formatCents` →
  `NumberFormat.simpleCurrency`), segura com o teto de R$ 10 milhões. Colar
  `1.234,56` (pt) ou `1,234.56` (en) dá `123456`. `LyTextField` ganhou
  `inputFormatters`. `AppConfig.billingBaseUrl` (`BILLING_BASE_URL`, padrão
  `http://localhost:8085`) e `billingApiClientProvider`.
- Acesso: `billingAccessProvider` (owner / `coachOperator` / `statusOnly` /
  `none`). O coach lê `coach_billing_access` de `GET /v1/tenant` (todo papel
  lê) — não precisou de mudança no backend; enquanto carrega, o coach não tem
  aba. A configuração fica viva a sessão toda: se o owner desligar o acesso, o
  coach só percebe ao receber 403 `billing_access_denied` (a lista invalida o
  tenant e a aba some) ou ao reabrir o app. Dívida baixa, consistente com o
  cache de 30 s do billing.
- Shell do coach: abas guardadas por identidade (`_CoachTab`), não por índice,
  porque o Financeiro aparece quando a configuração chega. Financeiro =
  Faturas (filtros de situação e mês, tabela >= 840 px, cursor) e Planos (só
  owner: criar, editar, arquivar; arquivado é só leitura — a API não tem
  "desarquivar"). Dar baixa = diálogo de confirmação (valor integral, data
  opcional, observação) com `Idempotency-Key` gerada **por abertura do
  diálogo** (repetir depois de queda de rede não duplica); hoje = não manda data
  (o servidor usa o relógio dele e o fuso do tenant). Estornar (owner) busca
  `GET /invoices/{id}` para achar a baixa vigente, exige motivo. Toque na
  fatura abre o detalhe com pagamentos e estornos. **Cancelar fatura
  (`POST /invoices/{id}/cancel`, owner) ficou de fora** — não consta nos passos
  do plano; a rota existe quando o owner precisar.
- Ficha: aba Financeiro (sempre a última; só owner e coach `own_students`) com
  a assinatura vigente (criar com plano/valor/dia 1–28/início, editar valor e
  dia — valem da próxima fatura —, pausar, retomar, cancelar com confirmação) e
  o histórico de faturas. Valor igual ao do plano não é enviado (o servidor usa
  o do plano). O `TabController` acompanha a quantidade de abas sem perder a
  atual.
- Selo "inadimplente": `StudentRow.billingStatus` vem de uma consulta em lote
  por página (`students/status`, 1 chamada ≤ 50 ids) junto do overview do
  workout; falha do billing = sem selo, a lista segue. Na ficha, `DelinquentBadge`
  na aba Dados. `billingVersionProvider` sobe a cada baixa/estorno/assinatura e
  recarrega lista e selo. Fatura de conta excluída mostra o selo "conta
  excluída" (a P7.5 é que liga o `account_deleted` no servidor).
- Inativar aluno com assinatura ativa: depois de inativar, diálogo "Assinatura
  ainda ativa" com atalho "Cancelar assinatura" (a consulta da assinatura é
  cortesia: erro = sem aviso).
- Organização: `SwitchListTile` (salva na hora) com texto diferente para cada
  modo. "Minhas mensalidades" (`/my-invoices`) na Conta do aluno, só leitura.
- `plan_archived` do billing é remapeado no repositório para
  `billing_plan_archived` (o mesmo código existe no workout com outro sentido).
  Erros novos nas 3 ARBs: `billing_access_denied`, `invoice_already_paid`,
  `invoice_canceled`, `payment_already_reversed`, `payment_is_reversal`,
  `idempotency_key_conflict`, `subscription_exists`,
  `invalid_subscription_state` (sem o `status` no texto).
- Testes (+34): máscara pt/en, lista/filtro/baixa/estorno/matriz, planos,
  assinatura (criar, valor próprio em centavos, pausar/retomar/cancelar),
  matriz de acesso, shell por papel, selo na lista e na ficha, aviso ao
  inativar, "Minhas mensalidades", toggle da Organização. `FakeBillingRepository`
  em `test/features/billing/billing_fakes.dart`.
- Pendente de verificação manual (nada foi rodado contra o billing real): fluxo
  completo no Chrome com owner (criar plano, assinar, baixa, estorno), coach
  nos dois modos, aluno em "Minhas mensalidades". Exige `billing/.env` com
  `IDENTITY_URL` e `INTERNAL_TOKEN` (pendência da P7.1/P7.2) e CORS do billing
  incluindo a origem do Chrome.

