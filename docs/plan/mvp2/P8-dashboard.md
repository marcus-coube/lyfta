# P8 — Dashboard, dívidas e release 2.0

Meta da fase: o coach e o owner abrem o app e veem o estado do negócio e do
dia; dívidas do 1.0 que o 2.0 encosta são quitadas; o pacote fecha com E2E.

Refs normativas: ADR-007, ADR-011, ADR-015, ADR-016, ADR-017.
Depende de: P5, P6 e P7.

---

## - [x] P8.1 Agregações do dashboard (identity, workout, billing, comms)

**Objetivo:** cada serviço responde o seu pedaço; o app compõe (sem BFF).
**Passos:**
1. identity: `GET /v1/students/stats` → ativos, inativos, convites pendentes,
   novos no mês (fuso do tenant). Coach: só os dele; owner: todos, com
   `?coach_id=` opcional.
2. workout: `GET /v1/coach/today` → alunos do vínculo com o estado de hoje no
   fuso da claim `tz`: `trained` (sessão finalizada), `in_progress`, `pending`
   (tem plano ativo e não treinou), `no_plan`; mais "sem treinar há 7+ dias".
   Reusa a consulta do `/internal/v1/pending-students` da P3.4.
3. billing (owner): `GET /v1/billing/summary?period=` → recebido no mês, a
   receber, vencido (valor e nº de faturas), nº de inadimplentes; série dos
   últimos 6 meses de recebido.
4. comms: `GET /v1/checkins/stats` → não revisados (já existe a fila; só a
   contagem).
**Aceite:** testes de handler de cada agregação (coach vê só o vínculo; coach
recebe 403 no summary); números batem com um seed conhecido.

## - [ ] P8.2 App — dashboard do coach e do owner (Flutter)

**Objetivo:** primeira aba do shell do coach/owner.
**Passos:**
1. `features/dashboard/`: cards de alunos ativos, check-ins não revisados,
   treinos de hoje (feito/pendente com atalho para a ficha), alunos sem treinar
   há 7+ dias; owner a mais: receita do mês, a receber, vencido, inadimplentes
   e gráfico de 6 meses (`fl_chart`, já pinado).
2. Cada card carrega e falha sozinho (skeleton/retry da P4.2): um serviço fora
   do ar não derruba o dashboard.
3. Grid responsivo (desktop-first na web, coluna no celular); owner pode
   filtrar por professor.
**Aceite:** dashboard reflete o seed do P8.1; card com serviço fora mostra
retry sem afetar os outros (teste de widget); coach não vê cards de valor.

## - [ ] P8.3 Dívidas do 1.0 que o 2.0 encosta

**Objetivo:** fechar o que as telas novas tornariam pior se ficasse.
**Passos:**
1. **Locale dinâmico do conteúdo** (dívida do P1.8): o app manda
   `Accept-Language` com o idioma da tela; biblioteca, modelos e `/me/today`
   resolvem tradução por ele (fallback pt-PT→pt-BR→en, ADR-011), não pelo
   locale do tenant.
2. **Contraste e toque** (P4.3): tokens semânticos usados como texto ≥ 4,5:1
   no tema dark; alvos ≥ 48 dp nos itens anotados e nas telas novas do 2.0.
3. **Paginação** dos check-ins acima de 200 (P3.5).
4. `created_by` nas tabelas do `assessment` (dívida da P2.2/P2.3), agora que
   coach e aluno escrevem na mesma ficha.
**Aceite:** trocar o idioma da tela para en muda o nome dos exercícios do seed;
script de contraste (ou teste) cobre os tokens dark; itens anotados com teste
ou verificação registrada nas Notas.

## - [ ] P8.4 E2E do 2.0 e release 2.0.0

**Objetivo:** pacote validado ponta a ponta sem regredir o 1.0.
**Passos:**
1. Roteiro `docs/plan/mvp2/e2e-2.md`: owner ajusta fuso → cria plano de
   mensalidade → convida coach → coach convida aluno → ficha com objetivo e
   lesão → coach cria modelo com superset e aplica a 2 alunos → aluno executa
   o superset offline no emulador → sync → owner assina o aluno → job gera a
   fatura (relógio/forçar tick) → vence → selo inadimplente e dashboard → aluno
   tenta excluir a conta e é bloqueado → baixa manual → estorno → baixa de novo →
   owner liga o toggle e o coach dá baixa num aluno dele → inativar aluno (aviso de assinatura) → login do aluno
   falha → reativar.
2. Repetir o roteiro final do 1.0 ([e2e-final.md](../mvp1/e2e-final.md)) como
   regressão.
3. Varredura: `flutter analyze` zero; `go vet`+testes nos 5 serviços;
   versão `2.0.0+N`; builds conforme ADR-015 (loja segue manual e fora).
**Aceite:** roteiro 2.0 e regressão do 1.0 verdes no Android (emulador) e no
Chrome; iOS no simulador quando disponível; pendências classificadas (bloqueia
release × vai pro 3.0).

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

**P8.1 (Mac, 2026-11-11)**
- Endpoints (owner|coach, JWT): identity `GET /v1/students/stats`
  (`active`, `inactive`, `pending_invites`, `new_this_month`); workout
  `GET /v1/coach/today`; billing `GET /v1/billing/summary?period=AAAA-MM`
  (só owner); comms `GET /v1/checkins/stats` (`unreviewed`). Em todos, coach
  conta só o vínculo; owner conta tudo e aceita `?coach_id=` (ignorado para
  coach puro; o summary do billing é do tenant inteiro, sem filtro).
- **M2M novo (não previsto no passo 2):** identity `GET /internal/v1/students?tenant_id=`
  devolve os ids dos alunos `active` do tenant. O `coach/today` do owner sem
  `coach_id` precisa de "todos os alunos" e só o identity sabe quem não tem
  plano (`no_plan`); `coachlink.ActiveStudentsOfTenant` no workout. Para coach
  (ou owner com `coach_id`) usa `StudentsOf` + `ExistingStudents` e descarta
  quem não é `active`. Identity fora do ar = 500 (nunca lista vazia).
- Definições: `new_this_month` = alunos criados desde o dia 1 no fuso da claim
  `tz` (convidados incluídos, excluídos fora); `pending_invites` = alunos
  `invited`. `coach/today`: dia = [00:00, 24:00) no fuso `tz`, critério
  `received_at` (mesmo do `find_pending_students`); `trained` = sessão
  finalizada hoje, `in_progress` = sessão hoje sem `finished_at`, `pending` =
  plano ativo (`student_plan_state`) e nada hoje, `no_plan`; precedência nessa
  ordem. Resposta: `date`, `counts` (os 4 estados + `stale`) e `items`
  (`student_id`, `state`, `last_session_at`, `stale`). `stale` = nunca treinou
  ou último `received_at` há 7+ dias — **aluno novo sem treino aparece como
  stale**; a P8.2 pode esconder quem acabou de entrar se incomodar. Nomes não
  vêm aqui: o app cruza com a lista de alunos (sem BFF).
- Billing `summary`: recebido = faturas `paid` com `paid_at` no mês (fuso do
  tenant); a receber = `open` com vencimento no mês; vencido = `overdue` de
  qualquer mês (estoque atual) em valor, nº de faturas e nº de alunos distintos;
  `received_series` = 6 meses terminando em `period` (ordem crescente). Valores
  em centavos. Coach recebe 403 `billing_access_denied` mesmo em `own_students`.
- Sem migration nova. Testes: `TestStudentStats` (identity),
  `TestCoachToday` (workout: seed com os 4 estados, virada de dia no fuso
  UTC+14, vínculo, owner/filtro, 403 de aluno, identity fora), `TestBillingSummary`
  (seed conhecido, virada de mês SP × UTC, 403 do coach) e `TestCheckinStats`
  (comms).
