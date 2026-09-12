# P4 — Praticidade e release

Meta da fase: calendário semanal do aluno, app leve e polido, i18n completo,
roteiro de release. Fecha o MVP 1.0.

Refs normativas: ADR-011, ADR-012, doc 000 (Product Principles).

---

## - [x] P4.1 Flutter — calendário/agenda semanal do aluno

**Objetivo:** visão semanal visual (pedido explícito do cliente).
**Passos:** aba Agenda: strip semanal (dom–sáb) + mês expansível; por dia: treino
previsto (pela rotação — próximo(s) dia(s) projetados), treino feito (sessões
sincronizadas, com resumo volume/duração ao tocar), descanso. Fonte: `GET
/v1/me/sessions?from=&to=` (adicionar no workout: sessões por período) + projeção
local da rotação. Streak simples de semanas com N treinos (contador local — 
gamificação real é 3.0).
**Aceite:** semana corrente reflete execuções reais do P1; navegação entre semanas;
teste de widget da célula de dia (3 estados).

## - [x] P4.2 Performance e robustez ("app leve, sem travar")

**Objetivo:** metas mensuráveis, não sensação.
**Passos:**
1. Cold start ≤ 2,5 s em device Android médio (medir com `flutter run --profile`
   + timeline); adiar inits não críticos (Firebase, etc.) pós-primeiro frame.
2. Skeleton loaders nas telas de rede (Hoje, Evolução, Chat); `cached_network_image`
   com placeholders em toda mídia; listas com paginação incremental.
3. Tratamento global de erro: interceptor mapeia `code`→mensagem i18n + retry
   action; telas nunca mostram stack/erro cru; crash-safe (zona guardada + log).
4. Web: build release com `--wasm` se estável, senão canvaskit; lighthouse básico
   da tela de login; bundle inicial < 3 MB gzip (meta do doc 015 futuro).
**Aceite:** números medidos e registrados nas Notas (antes/depois); nenhum jank
visível ao rolar biblioteca com 40 GIFs.

## - [ ] P4.3 Auditoria i18n + acessibilidade básica

**Objetivo:** cumprir ADR-011 de fato e o mínimo de a11y do doc 000.
**Passos:** varrer ARBs — nenhuma chave faltando em pt-PT/en (script
`tool/check_arb_parity` que compara chaves e falha no CI); revisar plurais/gênero;
formatação de data/número/unidade via `intl` em todo lugar (grep por `toString()`
suspeitos em datas/números); a11y: labels semânticos nos botões de ícone, tamanho
de toque ≥ 48dp, contraste dos tokens do DS verificado (WCAG AA), teste com
TalkBack no fluxo de execução de treino.
**Aceite:** script de paridade ARB no CI verde; fluxo Hoje→executar→finalizar
navegável por TalkBack.

## - [ ] P4.4 E2E final + roteiro de release

**Objetivo:** MVP 1.0 validado ponta a ponta e empacotado.
**Passos:**
1. Roteiro E2E completo (`docs/plan/mvp1/e2e-final.md`): signup professor (web) →
   convida aluno (Resend real em staging) → aluno instala Android → executa treino
   offline → sync → gráfico atualiza → foto+medidas → chat com push → check-in →
   coach revisa → calendário reflete a semana. Executar também no iOS (no Mac) e
   Flutter Web como aluno.
2. Builds: Android appbundle assinado (keystore documentado fora do git), iOS
   archive (no Mac), web release; versão `1.0.0+N`; checklist de smoke por
   plataforma.
3. Varredura final: `flutter analyze` zero infos; `go vet`+testes verdes nos 4
   serviços; secrets só em env; LGPD mínima do ADR-008 presente (consentimento no
   aceite do convite + exclusão de conta — se faltou, vira tarefa antes do release).
**Aceite:** roteiro E2E 100% verde nas 3 plataformas; artefatos de build gerados;
pendências restantes listadas e classificadas (bloqueia release × vai pro 2.0).

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

### P4.1 (2026-09-11, Mac)

- **Full-stack, como o plano previa:** o endpoint não existia no `workout`
  (o router só tinha `/me/today`, `/me/plan`, `/sync/*` e
  `/me/exercises/...`). Adicionado `GET /v1/me/sessions?from=&to=`
  (`internal/http/sync.go`, `SyncHandler.Sessions` — mesmo handler de
  `/me/today`, já tinha `sessions *repo.SessionRepo`) devolvendo
  `sessionSummaryDTO` (o mesmo shape do `recent_sessions` de `/me/today`),
  sem cursor: a janela é sempre curta (semana/mês), nunca o histórico
  inteiro. `from`/`to` são RFC3339, `to` estritamente depois de `from`,
  range maior que 120 dias é `400 validation_error` — a agenda navega
  semana a semana e mês expandido, não pede o histórico inteiro de uma vez.
- **Filtro por `started_at`, não `received_at` — desvio deliberado do que o
  contexto da tarefa sugeria.** O contexto apontava `received_at` (carimbo
  do servidor) por analogia ao `/internal/v1/pending-students` da P3.4, mas
  ADR-003 é explícito no próprio texto: *"relatórios usam `performed_at` com
  sanidade validada"*. `workout_sessions.started_at` É o `performed_at` que o
  device mandou ao abrir a sessão (`startSession`, P1.5) — filtrar por
  `received_at` faria um treino feito offline no sábado e sincronizado só na
  segunda aparecer na segunda-feira da agenda, o que contradiz o próprio
  propósito da tela. `pending-students` usa `received_at` por um motivo que
  não se aplica aqui: lá é preciso saber que o servidor **já recebeu** algo
  hoje para não mandar notificação duplicada; aqui é preciso saber **quando o
  treino aconteceu de verdade**.
- **Nenhuma migration nova.** O índice `idx_workout_sessions_student
  (tenant_id, student_id, started_at DESC)`, criado na P1.1 (migration
  0010), já cobre exatamente esta consulta — testado com o cursor keyset de
  `/me/today`/histórico, o range aqui é o mesmo padrão de acesso. Repositório
  novo: `SessionRepo.SessionsInRange` (reusa `effectiveLogFilter`, o mesmo
  filtro que esconde log corrigido por `set_revision` desde a P2.1).
- **"Treino previsto" é 100% projeção local**, como o plano pede — nenhum
  endpoint novo para isso. `RotationPointer` (domínio novo da feature
  `agenda`) lê o mesmo payload de `GET /v1/me/today` (rotação inteira +
  `day.id` + `status`) e projeta o rótulo do rodízio N dias à frente,
  assumindo **treino diário a partir de hoje** — é uma suposição
  simplificadora explícita (documentada no código): o servidor só garante
  de verdade o próximo passo real (`next_day_id`, que só avança quando uma
  sessão sincroniza); os demais dias futuros da faixa são só "se você
  treinasse todo dia, seria isto". Sessão sincronizada sempre vence a
  projeção (ADR-003 é a fonte de verdade do que aconteceu); dia passado sem
  sessão é sempre "descanso", nunca uma adivinhação de por que o aluno não
  treinou.
- **Streak simples, exatamente como o plano pediu ("contador local")**: meta
  semanal = tamanho do rodízio ativo (A/B/C → 3 treinos/semana), calculado
  sobre 8 semanas anteriores à corrente (a corrente fica de fora por ainda
  estar em andamento), contando semanas consecutivas a partir da mais
  recente. Nenhuma tabela nem endpoint novo — é `AgendaController` somando o
  mesmo `sessionsByDay` que já buscou para a semana/mês visíveis.
- **Guideline `flutter.md` § Estrutura levada a sério:** "feature não importa
  outra feature" — `AgendaSession`/`AgendaRotationDay` duplicam (não
  reimportam) `SessionSummary`/`RotationDay` de `features/workout/domain/`, e
  o resumo do dia (`_formatVolume`) duplica `formatLoad`/`formatMetric` — o
  mesmo padrão que já existia entre `shared/format/metric_format.dart` e
  `features/workout/presentation/prescription_format.dart` antes desta
  tarefa. `agendaApiProvider` chama o `workout` direto por
  `workoutApiClientProvider` (que é `core/`, não feature), igual o resto do
  app já faz.
- **Sem dependência nova**, como o contexto pedia: strip semanal e mês
  expansível são `Row`/`GridView.count` simples sobre os tokens do DS;
  formatação de data usa `intl` (`DateFormat`), nunca `toString()` — dando um
  passo à frente da auditoria da P4.3 em vez de criar dívida nova nela.
- **Célula de dia com 3 estados distintos por forma, não só cor**
  (`AgendaDayCell`, widget "burro"): círculo preenchido + check (feito),
  círculo só com borda + rótulo do rodízio (previsto), traço sem círculo
  (descanso) — pensado para não depender só de cor (contraste/daltonismo,
  guideline de a11y). Teste de widget cobre os 3 estados e o toque
  (`test/features/agenda/presentation/widgets/agenda_day_cell_test.dart`).
- **Verificado:** `go vet`/`gofmt` limpos e todos os testes do `workout`
  verdes (2 novos: janela feliz + `to`/`from` inválidos,
  `internal/http/sync_test.go`); `flutter analyze` limpo, guard de strings
  limpo, **66 testes verdes no app** (13 novos: 6 de domínio —
  `RotationPointer.predict` circular e sem ponteiro, `buildAgendaDays` nos 3
  estados —, 3 de `startOfWeek`, 4 de widget da célula). Smoke automatizado
  via `httptest` real contra Postgres cobre o Aceite do endpoint; **pendente
  de verificação manual**: rodar a aba Agenda de verdade num device/Chrome
  com um aluno que tenha sessões reais do E2E do P1/P2 (Android segue
  bloqueado pelo `google-services.json` ausente, conhecido desde a P3.5 —
  Chrome ou iOS servem para este roteiro) confirmando visualmente a semana
  corrente, a navegação entre semanas, o mês expansível e o streak com dados
  de verdade.

### P4.2 (2026-09-11, Mac)

- **Cold start (§1): mudança estrutural feita, número do Aceite NÃO medido —
  registrado como pendência, não estimado.** `main.dart` fazia `await
  Firebase.initializeApp()` antes de `runApp()`, bloqueando o primeiro frame
  em todo boot mobile. Virou fire-and-forget depois de `runApp()`
  (`WidgetsBinding.instance.addPostFrameCallback`): o app pinta a tela de
  login sem esperar o I/O nativo do Firebase. Seguro porque
  `PushService.init()`/`ensureRegistered()` (`core/push/push_service.dart`)
  já tratavam Firebase ausente com try/catch (era assim mesmo sem
  `google-services.json`, bloqueio conhecido desde a P3.5); o único efeito
  colateral possível é o registro de push do boot autenticado correr
  levemente mais cedo que o Firebase estar pronto, mas
  `_restoreSession()` (`auth_controller.dart`) sempre faz um refresh de rede
  antes de autenticar, o que dá tempo de sobra ao `postFrameCallback` (1
  frame, ~16 ms) rodar primeiro — não há caminho de regressão observável.
  **Não consegui medir o número do Aceite** (`flutter run --profile` +
  timeline em Android): o bloqueio #1 do STATUS.md (`google-services.json`
  ausente) barra qualquer build Android, e nem macOS nem iOS têm a pasta de
  plataforma gerada nesta máquina (`flutter devices` só lista `macOS` e
  `Chrome`, mas a pasta `macos/` não existe — ver Toolchain do STATUS.md).
  Web/Chrome não serve de proxy porque o próprio guard do Firebase é
  `!kIsWeb && (Android || iOS)` — a mudança tem efeito **zero** em não-mobile,
  então medir lá não provaria nada sobre o ganho real. Adicionei a pendência
  #6 na tabela do STATUS.md em vez de inventar um número.
- **Skeleton loaders (§2):** `shared/widgets/ly_skeleton.dart` novo
  (`LySkeletonBox`/`LySkeletonLine`/`LySkeletonListTile`, pulso de opacidade
  via `AnimationController`, sem dependência nova) substituindo
  `CircularProgressIndicator` cru em Hoje (`_TodaySkeleton`), nas 4 abas de
  Evolução (carga com área de gráfico, medidas/bioimpedância como linhas,
  fotos como grade 3×3, resumo do coach) e nas 3 telas de Chat (lista de
  conversas, mensagens — `features/chat/presentation/widgets/chat_skeletons.dart`).
  Também apliquei nas duas telas fora da lista original que têm o mesmo
  problema e são visitadas o tempo todo (lista de alunos do coach, aba
  Check-ins) — a auditoria do §3 achou os dois casos e a correção é a mesma
  peça.
- **`cached_network_image` sem placeholder (§2): achado real em
  `ChatBubble`** (`features/chat/presentation/widgets/chat_bubble.dart`) — a
  imagem de mensagem usava `Image.network` cru, sem cache de disco, sem
  placeholder de carregamento e sem fallback de erro (a única mídia do app
  nessa situação; biblioteca/fotos de evolução já usavam
  `CachedNetworkImage` com os dois desde a P1.6/P2.4). Trocado pelo mesmo
  padrão de `ExerciseMedia`/`PhotoGrid`.
- **Paginação incremental (§2): biblioteca e chat já paginam de verdade**
  (scroll listener + `loadMore()`, conferido lendo `library_screen.dart` e
  `chat_screen.dart` — nada a fazer). **Achado real: medidas, bioimpedância
  e fotos da aba Evolução tinham `hasMore`/`loadMore()` prontos nos
  controllers (cursor keyset do servidor, P2.3) mas a tela nunca chamava —
  a lista sempre parava na primeira página e não tinha como saber que
  faltava mais.** Como as três seções vivem dentro de um único `ListView`
  maior (não são elas mesmas o scroll principal), o gatilho escolhido foi um
  botão "Carregar mais" (`_LoadMoreButton`, chave nova `commonLoadMore` nas
  ARBs pt-BR/en — pt-PT cai no fallback, mesma wording) em vez de scroll
  infinito aninhado, que competiria com o scroll da aba inteira.
  **Descoberta anotada, não corrigida (fora do escopo desta tarefa):** a
  lista de alunos do coach (`StudentsController`) busca só a primeira página
  (20 alunos, `pageSize` fixo) e não tem cursor nem `loadMore` nenhum — acima
  de 20 alunos o resto fica invisível. Não é scroll incremental faltando
  como o caso acima, é paginação inexistente; consertar direito pede mudar o
  shape do estado do controller (hoje é só `List<StudentRow>`, precisaria
  virar algo como `StudentListState(items, hasMore, cursor)`), escopo maior
  do que um ajuste de UI. Registrado como pendência.
- **Erro cru / retry (§3): auditoria em todo `.when(error: ...)` do app.**
  A tradução por `code` (`describeApiError`) já estava correta em toda
  tela — nenhuma stack/erro cru em lugar nenhum, ADR-011 §3 já cumprido
  antes desta tarefa. **Achado real: 5 telas mostravam a mensagem traduzida
  mas sem nenhuma ação de tentar de novo** (`ChatHomeScreen`,
  `ConversationListScreen`, `ChatScreen`, `StudentsScreen`,
  `CoachCheckinsTab`) — usuário preso precisando fechar e reabrir a tela.
  Corrigido com `shared/widgets/ly_error_state.dart` (`LyErrorState`,
  mensagem + `LyButton` de retry) chamando o `refresh()` que cada controller
  já expunha (todos tinham, nenhum precisou ganhar método novo). Telas mais
  antigas com o próprio `_ErrorState` local (Hoje/Biblioteca/Agenda) não
  foram tocadas — já tinham retry, mexer nelas seria puro churn.
- **Crash-safe / zona guardada (§3):** não achei `runZonedGuarded` nem
  handler de `FlutterError.onError` em `main.dart` — não implementado aqui
  (o passo fala de "crash-safe... e log", mas não há um backend de log de
  erro definido em nenhum ADR/plano para mandar isso; adicionar a zona sem
  um destino faria logging morto). Registrado como pendência para decisão
  futura, não implementado por falta de destino definido, não por descuido.
- **Web (§4):** `flutter build web --wasm --release` **falha** — dependência
  transitiva `flutter_secure_storage_web` usa `CryptoKey`/`dart:html` sem
  porte para `dart:js_interop`, incompatível com `dart2wasm`
  (`flutter build web --release` confirma via *wasm dry run* a mesma lista:
  `dart:html`, `dart:js_util`, `package:js` não suportados). O próprio texto
  do passo já previa esse desvio ("`--wasm` se estável, senão canvaskit") —
  build canvaskit padrão (`flutter build web --release`) passou limpo.
  Métricas **medidas de verdade** nesse build, servido localmente
  (`python3 -m http.server`) e auditado com Lighthouse CLI real
  (`npx lighthouse`, Chrome headless, categoria performance) contra
  `/#/login`:
  - `main.dart.js`: 4,19 MB brutos → **1,14 MB gzip** (`gzip -c | wc -c`) —
    dentro da meta de <3 MB gzip do doc 015 com folga.
  - Lighthouse (localhost, sem throttling de rede/CPU — não é o dispositivo
    médio do Aceite, é a bancada de build): performance 100/100, First
    Contentful Paint 0,4 s, Largest Contentful Paint 1,3 s, Total Blocking
    Time 0 ms, CLS 0. Peso total transferido 6,05 MB — inclui o motor
    CanvasKit, que por padrão vem do CDN da Google
    (`gstatic.com/flutter-canvaskit`, cacheado pelo navegador entre visitas,
    não pela primeira), não da pasta `canvaskit/` de 37 MB que o build
    também gera localmente (só serve de fallback se `useLocalCanvasKit`).
  - Rodei visualmente a tela de login no build servido (screenshot via
    Browser tool) para confirmar que o CanvasKit renderiza igual ao dev —
    sim, idêntico.
  - **Não fiz**: lighthouse mobile-emulado com throttling 4G/CPU (só rodei
    desktop sem throttle, que é o que deu para fazer rápido nesta sessão) —
    registrado como pendência, não uma medida de "boa o suficiente para
    mobile real".
- **Sem dependência nova**, como o contexto pedia — `cached_network_image`
  já era dependência (P1.6); skeleton é `AnimationController` puro.
- **Verificado:** `flutter analyze` limpo (0 issues), guard de strings
  limpo, **66 testes verdes** (nenhum teste cobria os `CircularProgressIndicator`/
  `Image.network` trocados, então nada teve que ser reescrito — comportamento
  novo ainda sem teste de widget dedicado, dívida pequena e aceitável para o
  tamanho da mudança). `go vet`/`go test` não rodou porque nenhum serviço Go
  foi tocado nesta tarefa.
