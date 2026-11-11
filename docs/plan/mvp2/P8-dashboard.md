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

## - [x] P8.2 App — dashboard do coach e do owner (Flutter)

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

## - [x] P8.3 Dívidas do 1.0 que o 2.0 encosta

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

**P8.2 (Mac, 2026-11-11)**
- `features/dashboard/` (domain, data, presentation) e aba **Início** como
  primeira e padrão do shell do professor (owner e coach). `DashboardRepository`
  usa os 4 clientes (identity, workout, billing, comms) e cada card tem o
  próprio `FutureProvider.autoDispose`: carrega com skeleton, falha com
  `LyErrorState` + retry e não afeta os outros (teste de widget com o `workout`
  e com o `billing` fora). Hoje e Sem treinar dividem o provider do
  `coach/today` (uma chamada, dois cards).
- **Decisão do `stale` (aviso do P8.1):** o card "Sem treinar há 7+ dias" lista
  só quem **já treinou** e parou (`stale && last_session_at != null`), do mais
  antigo ao mais recente, com "Há N dias". Quem nunca treinou fica de fora: aluno
  novo não é abandono, e se tem plano já aparece como pendente em "Treinos de
  hoje"; sem plano, entra na contagem "sem plano ativo". A contagem vem dos
  `items`, não de `counts.stale`.
- Nomes: o `coach/today` só devolve ids; o app resolve por
  `GET /v1/users/directory` (já usado pelo chat) só para as até 6 linhas
  exibidas por card ("+N no total" além disso). Diretório fora do ar = rótulo
  genérico "Aluno", sem quebrar. Linha tocável (>= 48 dp) abre `/students/:id`.
- Owner: filtro por professor (`?coach_id=` nos 3 cards que aceitam; o
  `billing/summary` é do tenant inteiro) e dois cards a mais (recebido / a
  receber / vencido / inadimplentes e gráfico `fl_chart` de 6 meses, tooltip em
  moeda). Coach não monta os cards de valor nem chama o `billing` (teste).
  Período do summary omitido: o servidor usa o mês corrente no fuso do tenant.
- Grade: 2 colunas a partir de 840 px (mesmo corte do shell), 1 no celular.
- Testes: `test/features/dashboard/` (seed com valores, coach sem valor, retry
  isolado de `workout` e `billing`, layout estreito). Testes de shell, roteador
  e login que caem na aba inicial passaram a injetar `FakeDashboardRepository`
  (o skeleton anima para sempre e travaria o `pumpAndSettle`).
- Pendência: o gráfico só foi exercitado em teste de widget; checagem visual no
  Chrome/emulador fica para o E2E do P8.4.

**P8.3 (Mac, 2026-11-11)**
- **Locale:** o `workout` resolve o idioma por `?locale=` > `Accept-Language` >
  claim `locale` (a do tenant); `Accept-Language` desconhecido é ignorado (não
  dá 400), `q` respeitado. Vale para biblioteca, modelos, planos, `/me/today` e
  pull (todos passam por `requestLocale`). No app, `AcceptLanguageInterceptor`
  entra em todo `ApiClient` e manda o idioma resolvido do aparelho
  (`pt-BR`/`pt-PT`/`en`), lido a cada requisição. O app não tem seletor de
  idioma próprio: "idioma da tela" = o do aparelho. Testes: unitário do parser,
  `TestLibraryFollowsAcceptLanguage` (nome do seed muda com `en`; `?locale=`
  vence o cabeçalho) e teste do interceptor. Pendência: o treino do dia já
  baixado fica no idioma de quando foi sincronizado até o próximo pull.
- **Contraste:** `test/core/design_system/ly_colors_contrast_test.dart` cobre
  todo token de texto do dark (primário, secundário, accent, 4 semânticos) sobre
  background/surface/elevated, e `onAccent` sobre `accent`: todos >= 4,5:1, sem
  mexer em cor. O tema light segue fora (inatingível, `ThemeMode.dark` fixo).
- **Toque 48 dp:** retry/remover da bolha que falhou no chat (dívida nomeada da
  P4.3, teste de widget mede o `InkWell`), link "Novo por aqui?" do login, nota
  do check-in (44 -> 48) e toggle do banner de lesões do builder. Telas novas do
  2.0 (dashboard, financeiro, alunos): auditadas por leitura, usam
  `ListTile`/`LyButton`/`InkWell` com `minHeight: 48`; sem outro achado. Não
  medido em aparelho.
- **Paginação:** o servidor já paginava check-ins por cursor (teto 50) e o
  diretório de nomes do chat já busca por ids em lotes de 100 — o que faltava
  era a UI da aba Check-ins do coach, que parava nos 30 primeiros. Botão
  "Carregar mais" + `loadMore` sem duplicar toque e sem perder a lista se a rede
  falhar (teste de widget com duas páginas).
- **`created_by`:** migration `0006_created_by` no assessment (medidas,
  bioimpedância, fotos), `NOT NULL`; linhas existentes foram preenchidas com o
  `student_id` (o autor real não foi guardado; só afeta dado de dev). Handlers
  gravam o `sub` do token; a API devolve `created_by` (aditivo). Testes: repo
  (aluno e coach voltam) e HTTP (aluno na `/me`, coach na ficha). Sem exclusão
  de coach hoje: `created_by` de coach removido ficaria órfão (só um id).

**P8.4 (Mac, 2026-11-11) — em andamento, checkbox em aberto**
- Feito: roteiro [e2e-2.md](e2e-2.md) (40 passos, colunas API/Android/Chrome/iOS);
  varredura verde (`flutter analyze` zero, 231 testes Flutter, `go vet` + `go test
  -count=1` nos 5 serviços — `backend/` só tem identity, workout, assessment,
  comms e billing); versão `2.0.0+1` (pubspec, default de `APP_RELEASE` e README);
  `flutter build web --release` e `flutter build apk --release` (75,5 MB) ok, sem
  loja (ADR-015).
- Execução (detalhe e motivos no e2e-2.md): 36/40 passos pela API real; Android
  (emulador): login, bi-set offline por rodada, fila, sync, Evolução e Agenda;
  Chrome: dashboard do owner com valores e gráfico, Financeiro, selo
  "inadimplente", card com serviço fora com retry. iOS não executado; regressão
  do 1.0 só parcial.
- **Falha achada e corrigida:** `ListAfter` do identity cortava a linha extra da
  paginação e a varredura M2M de tenants parava em 500 (billing e comms ignoravam
  o resto). Commit `fix(p8.4)` com teste.
- **Por que o checkbox fica aberto:** o Aceite pede roteiro 2.0 e regressão do 1.0
  *verdes* no Android e no Chrome. Não estão: a maior parte do lado do coach/owner
  foi validada por API, não por tela, e a regressão do 1.0 não foi repetida inteira.

**P8.4 — rodada de tela no Chrome (Mac, 2026-11-11, tenant `e2e-ui-1111`)**
- Build web release servido em 3 origens (5790 owner, 5791 coach, 5792 aluno) sobre
  a pilha 9181-9185; navegador em en. Detalhe por passo no e2e-2.md.
- Pela tela: 1-3, 5, 7-13, 17, 18, 21-26, 28-31, 33, 35-37 ✅; 4 e 6 ⚠️ (abaixo).
  Inclui o player web do bi-set por rodada (volume 1.680) e o check-in.
- **Sessão web persiste** (FlutterSecureStorage no `localStorage`) e é
  **compartilhada entre abas da mesma origem**: aceitar um convite numa aba troca a
  conta da outra. Corrige a nota anterior "sessão não persiste na web". Para o E2E,
  um papel por origem (ou janela anônima).

*Achados da rodada de tela:*
- **A1 — owner não tem tela para convidar coach** (passo 4): o convite da aba Alunos
  só cria aluno; o coach só entra por API. Sem isso, academia com mais de um
  professor não opera pelo app.
- **A2 — bi-set montado no builder descansa entre exercícios**: o builder preenche
  `Rest 60 s` em toda série e o `BlockRunner` respeita o descanso prescrito por série
  dentro da rodada (regra da P6.5), então o aluno descansa 60 s entre supino e
  remada, contra o texto do próprio bloco ("rest only at the end of each round").
- A3 — o coach só vê a aba Financeiro depois de recarregar/relogar quando o owner
  liga `own_students` (`tenantSettingsProvider` lido uma vez por sessão).
- A4 — a baixa manual pede só data e nota; o roteiro falava em "forma" de pagamento.
- A5 — "Start" da assinatura vem com a data do navegador, não a do fuso do tenant
  (Auckland já estava em 12/11).
- A6 — banner do builder em modo modelo fala em "aluno" ("The student still sees…").
- A7 — o aceite de convite exige "dados de saúde (obrigatório)" também do coach.

*A1 e A2 corrigidos (2026-11-11, decisão do usuário):*
- A1: o diálogo "Convidar" da aba Alunos ganha, só para o owner, a escolha
  Aluno/Professor (`role: coach` no mesmo `POST /v1/invitations`); professor
  convidado não entra na lista de alunos, então a tela confirma por mensagem.
  Coach segue só convidando aluno. Verificado na tela (201, `role = coach`).
- A2: em bloco por rodada (`BlockType.isRounds`: bi-set e circuito) a série nasce
  sem descanso próprio, e virar um bloco para bi-set/circuito limpa o descanso
  das séries que só copiava o do bloco; o descanso do bloco vale ao fim da
  rodada (regra da P6.5 inalterada no `BlockRunner`). Planos já salvos com 60 s
  por série não são migrados (sem usuários). Verificado na tela: "Rest (s)" vazio
  nas séries do bi-set.
- Testes de widget novos nos dois; `flutter analyze` zero, 234 testes.

*Pendências — bloqueiam o release 2.0.0 (fechar a P8.4):*
1. (A1 e A2 resolvidos acima.)
2. Android: Minhas mensalidades, bloqueio da exclusão com a mensagem e o atalho,
   login de aluno inativo e troca de idioma do aparelho (passos 9, 24, 25, 34, 36, 39)
   — os mesmos fluxos passaram na tela web.
3. Regressão do 1.0: smoke do e2e-final (13 linhas) no Android e no Chrome, e a
   foto, a bioimpedância, o chat com imagem/WS e o mês/streak da Agenda.
4. iOS no simulador "quando disponível" — não bloqueia o APK/web, mas repetir
   antes da primeira subida para loja (segue a lista pré-loja L1-L10).

*Pendências — vão para o 3.0 (ou decisão do usuário):*
- Sem tela de aceite de convite no mobile (o link abre a versão web).
- Token de acesso emitido antes da inativação vale até expirar (sem revogação).
- A3-A7 acima.
- "Carregar mais" dos check-ins sem dado real (> 30 check-ins); só teste de widget.
- Treino do dia já baixado fica no idioma do último pull (nota da P8.3).
- Criar assinatura já gera a fatura do mês: o job só gera de fato a do mês seguinte
  (comportamento do ADR-017, só registrado para o roteiro).
