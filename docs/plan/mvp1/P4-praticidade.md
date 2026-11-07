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

## - [x] P4.3 Auditoria i18n + acessibilidade básica

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

## - [x] P4.5 LGPD mínima — consentimento + exclusão de conta (identity, workout, assessment, comms, Flutter)

**Objetivo:** cumprir ADR-008 §1, §2 e §6 antes do release (achado da P4.4).
**Passos:**
1. **Termos versionados (§6):** política de privacidade + termos de uso em
   `app/assets/legal/` (pt-BR fonte, pt-PT, en), com versão explícita
   (`TERMS_VERSION`, ex. `2026-11-v1`) compartilhada por app e identity via env.
2. **identity — `consents`** (`tenant_id`, `user_id`, `purpose`, `granted_at`,
   `revoked_at`, `terms_version`; RLS + índice por `tenant_id`). Finalidades no
   MVP: `health_data` (obrigatória para usar o app como aluno) e
   `progress_photos` (opcional). GPS fica para o running (4.0).
   `GET /v1/me/consents`, `PUT /v1/me/consents` (concede/revoga, append-only:
   revogar grava `revoked_at`, nunca apaga linha). Claims do JWT ganham as
   finalidades vigentes, para os outros serviços checarem sem chamada síncrona.
3. **Coleta:** aceite do convite (aluno) mostra os termos e as duas finalidades
   separadas, `health_data` obrigatória; `POST /v1/invitations/accept` passa a
   exigir os consentimentos. Signup do owner exige aceite dos termos (sem
   finalidades de saúde). **Gate:** aluno logado sem consentimento vigente na
   versão atual dos termos (usuários antigos, termo novo) cai na tela de
   consentimento antes do app.
4. **Revogação:** tela de privacidade no perfil (aluno) para ver/revogar
   `progress_photos`. Sem ela, o `assessment` recusa upload de foto (403) e o
   coach deixa de ver as fotos do aluno.
5. **Exclusão de conta (§2), self-service** para aluno e coach; owner recebe
   erro explicativo (encerrar tenant é outro fluxo, fora do MVP).
   `DELETE /v1/me` no identity orquestra, com confirmação por senha:
   marca o usuário `deleting` (login bloqueado) → chama
   `DELETE /internal/v1/users/{id}` (`INTERNAL_TOKEN`, idempotente) em
   `assessment` (medidas, bioimpedância e fotos: **exclusão física**, inclusive
   objetos no S3), `workout` (execuções: **anonimizar**, sem titular; planos
   atribuídos: excluir) e `comms` (mensagens e check-ins: anonimizar autor;
   devices de push: excluir) → por fim anonimiza o usuário no identity
   (e-mail/nome/hash substituídos, tokens e convites invalidados). Falha num
   serviço = 502, usuário segue `deleting` e a chamada pode ser repetida.
6. **App:** "Excluir minha conta" no perfil, com aviso do que é apagado e
   confirmação por senha; ao concluir, logout e limpeza do banco local.
**Aceite:** aluno novo não entra sem consentir `health_data`; revogar fotos
bloqueia upload; exclusão apaga saúde/fotos (incluindo objetos no MinIO),
anonimiza execuções e mensagens, e o login do excluído falha; teste de handler
da orquestração (feliz + serviço fora do ar) e do endpoint interno de cada
serviço; teste de widget da tela de consentimento. Strings nos 3 idiomas.

---

## - [x] P4.6 Tratamento de crash e erros (Flutter + 4 serviços)

**Objetivo:** observabilidade mínima de erros do ADR-009 §5 (Sentry ou
GlitchTip, que fala o mesmo protocolo). Fecha a pendência da P4.2.
**Passos:**
1. **Flutter:** `sentry_flutter` (pinar). `runZonedGuarded` +
   `FlutterError.onError` + `PlatformDispatcher.instance.onError` em `main.dart`.
   DSN por `--dart-define=SENTRY_DSN`; vazio = desligado, erro só no console
   (dev e CI não mandam nada). `environment` e `release` (`1.0.0+N`) no evento.
2. **Go:** `sentry-go` (pinar no `backend/README.md`) em cada serviço,
   duplicado (ADR-013, sem pacote compartilhado). Middleware de `recover` que
   reporta panic e responde 500 JSON; 5xx reportados com `request_id`. DSN por
   env `SENTRY_DSN`, vazio = desligado.
3. **Privacidade (ADR-008):** `sendDefaultPii` desligado; evento leva só
   `user_id`/`tenant_id`, nunca e-mail, nome, corpo de requisição, medidas ou
   mensagens. Breadcrumbs HTTP sem query string nem headers de auth.
4. `.env.example` e app/README documentam as variáveis.
**Aceite:** com DSN vazio nada é enviado e o app/serviços se comportam como
hoje; teste do middleware de recover (panic vira 500 e não derruba o
processo); teste que o filtro de evento remove PII. Envio real verificado
manualmente quando houver projeto Sentry/GlitchTip (pendência humana).

---

## - [x] P4.7 Vínculo professor↔aluno (identity, workout, assessment, comms, Flutter)

**Objetivo:** cumprir o ADR-008 §3 antes do release. O coach só vê dados (saúde,
treino, chat, check-in) dos alunos vinculados a ele; o owner vê todos e
reatribui. Mecanismo e cardinalidade no
[ADR-016](../../adr/ADR-016-vinculo-professor-aluno.md). Fecha a dívida aberta
desde o P1.4.
**Passos:**
1. **identity, tabela `coach_students`** (migration `0012`):
   - colunas `tenant_id`, `student_id` (PK com o tenant), `coach_id NOT NULL`,
     `assigned_by`, `assigned_at`; RLS e índice `(tenant_id, coach_id)`;
   - **1 coach principal por aluno**;
   - backfill na migration: o primeiro `invitations.invited_by` do e-mail, se for
     um usuário ativo coach|owner; senão o owner ativo mais antigo;
   - o convite de aluno (`POST /v1/invitations`, que já cria o usuário
     `invited`) grava o vínculo com quem convidou;
   - `DELETE /v1/me` de coach move os alunos dele para o owner ativo mais antigo
     antes de anonimizar; de aluno, apaga a linha.
2. **identity, API:**
   - `GET /v1/users?role=student`: o coach sem `owner` só vê os seus; o owner vê
     todos, com `coach_id` por aluno e filtro `?coach_id=`;
   - `PUT /v1/students/{id}/coach` `{coach_id}`, só owner. O alvo precisa ser um
     aluno não excluído e o coach um usuário `active` com papel coach|owner;
     senão 422 `validation_error`;
   - M2M com `X-Internal-Token`: `GET /internal/v1/coaches/{id}/students?tenant_id=`
     devolve `{student_ids}` e `GET /internal/v1/students/{id}/coach?tenant_id=`
     devolve `{coach_id}`.
3. **Cliente `internal/coachlink`**, duplicado em workout, assessment e comms
   (ADR-013 §2), no modelo do `assessment/internal/consent`:
   - `StudentsOf(tenant, coach)` com cache em memória de TTL 30 s
     (`COACH_LINK_CACHE_TTL`); `CoachOf` só no comms;
   - helper `CanAccessStudent(claims, studentID)`: owner na claim libera sem
     chamada; senão, o aluno precisa estar no conjunto do coach;
   - falha do identity responde 500 (fecha o acesso);
   - `IDENTITY_URL` nova no workout e no comms (`.env.example`).
4. **workout:**
   - middleware `RequireStudentLink` no `Route("/students/{id}")` (plans,
     exercises/logged, history);
   - as rotas por plano (`GET /plans/{id}`, `PUT .../draft`, `POST .../publish`)
     checam `plan.StudentID`;
   - `authorizeWrite` passa a ser owner ou coach vinculado ao aluno, não mais o
     dono do plano: o coach reatribuído edita;
   - `POST /plans` checa o `student_id`, e o `coach_id` informado pelo owner
     precisa ser o coach vinculado.
5. **assessment:** o mesmo middleware no `Route("/students/{id}")` (medidas,
   bioimpedância, fotos, presign, summary), antes da checagem de
   consentimento.
6. **comms:**
   - `Start` checa o vínculo;
   - `loadParticipantConversation` e o presign de mídia exigem, quando o ator é o
     coach da conversa e não é owner, que ele seja o coach atual do aluno; o
     aluno segue lendo o próprio histórico;
   - `GET /conversations` do coach omite ex-alunos;
   - `GET /checkins` sem `student_id` filtra por `student_id = ANY(conjunto)`;
     com `student_id`, checa o vínculo;
   - `Review` carrega o check-in e checa o vínculo;
   - o push de dor forte vai só para o coach atual (`CoachOf`), não para todo
     coach com conversa aberta.
7. **Contrato de erro:** aluno não vinculado responde **404
   `student_not_found`** em todo serviço, indistinguível de aluno inexistente ou
   de outro tenant.
8. **App:**
   - `AuthState.isOwner` (hoje `owner` e `coach` viram o mesmo `UserRole.coach`);
   - só para o owner, o tile de aluno mostra o professor e a ação "Trocar
     professor": bottom sheet com coaches e owners que chama o `PUT`;
   - `student_not_found` vira mensagem i18n em evolução, check-ins e chat, com
     estado de erro sem retry;
   - strings nas 3 ARBs.

**Aceite:**
- o coach B recebe 404 em todo dado do aluno de A nos 3 serviços (teste
  cross-coach por serviço, com identity fake) e não vê o aluno na lista nem na
  fila de check-ins;
- o owner acessa tudo e reatribui; o novo coach passa a ver em até 30 s e o
  antigo perde o acesso;
- o backfill está testado;
- a exclusão de um coach não deixa aluno sem professor;
- o cliente `coachlink` tem testes de cache, de TTL e de identity fora do ar
  (vira erro);
- teste de widget do tile como owner e como coach.

**Limite de tentativas (ponto 1, commit `53588b7`):** o signup tem 10 por IP a
cada 5 min, e o aceite de convite e a troca de senha têm 10 falhas por IP. Os
testes que passarem disso no mesmo servidor de teste tomam 429.

**Fora de escopo:**
- N:N (coach assistente);
- histórico de vínculos (só `assigned_by` e `assigned_at`);
- escolher o coach no convite;
- desativar coach (`disabled` não tem endpoint);
- papel reception (não existe; o ADR-016 já o exclui de dado de aluno);
- arquivar a conversa do aluno com o ex-coach;
- invalidação ativa do cache por evento.

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

### P4.3 (2026-09-12, Mac)

- **Paridade de ARB, primeiro fato checado antes de qualquer coisa:** o
  commit anterior ("pt-PT completo — 291 chaves") já tinha fechado a
  paridade de verdade — `python3` contando chaves (excluindo `@meta`)
  confirmou **348/348/348** em pt-BR/pt-PT/en, sem chave faltando nem
  sobrando. O número "291" do commit era as chaves *traduzidas naquela
  sessão*, não o total do arquivo — só parecia incompleto porque a
  metadata `@chave` (só existe no template pt-BR para uso do gerador) infla
  a contagem bruta do arquivo (429 entradas em pt.arb vs 348 chaves reais).
  Consequência prática: não havia chave faltando para "descobrir" — o
  trabalho real da tarefa foi construir o *script* que a partir de agora
  garante isso no CI, e auditar formatação/a11y de verdade.
- **`app/tool/check_arb_parity.dart` novo** — Dart puro (`dart:io`+
  `dart:convert`, zero dependência nova), não bash/PowerShell duplicado
  como o guard de strings: `dart run` funciona igual em Mac/Windows/CI sem
  manter dois scripts. Compara chaves de `app_pt.arb` (template) contra
  `app_pt_PT.arb`/`app_en.arb` e falha (`exitCode = 1`) se faltar alguma;
  também compara os **placeholders declarados em `@chave.placeholders`**
  contra o texto de cada tradução — um `{count}` que sumiu na tradução (viraria
  texto solto ou quebraria a interpolação em runtime) não é pego pelo
  `flutter analyze` nem pelo gerador de l10n, que só valida o template.
  Testado nos dois sentidos: removi uma chave e um placeholder de
  `app_en.arb` na mão, confirmei exit code 1 com a mensagem certa, restaurei
  do git. Plugado no CI (`.github/workflows/ci.yml`, job `app`, depois do
  guard de strings).
- **Achado real #1 (formatação de número, ADR-011 §4): `formatLoad`/
  `formatMetric`/`formatSignedMetric` e a `_formatVolume` duplicada da
  agenda usavam `toString()` de `double` — que é **sempre** ponto decimal,
  nunca vírgula, não importa o locale.** Carga/volume/medidas em kg
  apareciam "42.5" para um aluno pt-BR que só deveria ver "42,5". Corrigido
  com `NumberFormat('#,##0.##', locale)` do `intl` (já dependência) nas 4
  funções, threading `locale`/`l10n.localeName` a partir do `context` em
  cada um dos ~13 call sites (`set_row.dart` — inclusive o campo *editável*
  de carga, que já aceitava vírgula na entrada mas mostrava ponto no
  pré-preenchimento, agora os dois lados batem —, `today_screen.dart`,
  `session_summary_sheet.dart`, `summary_card.dart`, `delta_badge.dart`,
  `measurement_list.dart`, `bioimpedance_list.dart`, `load_chart_panel.dart`,
  `agenda_day_details_sheet.dart`). Teste de widget do `set_row_test.dart`
  que antes **afirmava o bug** (`expect(..., '42.5')`) corrigido para
  `'42,5'` — é o teste que teria pego isso desde o P1.7 se alguém tivesse
  olhado com o locale certo. Confirmado com `NumberFormat` real que pt-PT
  usa separador de milhar diferente de pt-BR (espaço vs ponto) — a mesma
  razão pela qual ADR-011 não deixa pt-PT herdar cegamente de pt-BR.
- **Achado real #2 (mesma classe de bug): `ChatBubble._timeLabel` montava
  "HH:mm" na mão** (`hour.toString().padLeft(2,'0')`), sempre 24h para todo
  mundo. Trocado por `DateFormat.jm(locale)`, que respeita a convenção do
  locale (confirmado com script isolado: 24h em pt-BR/pt-PT, 12h com AM/PM
  em en — "3:05 PM" vs "15:05"). Teste de widget existente
  (`chat_bubble_test.dart`) já usava `Locale('pt')` e continuou verde sem
  mudança (pt não muda de formato).
- **Achado real #3 (a11y — botão de ícone sem rótulo):** de 15 `IconButton`
  no app, 14 já tinham `tooltip` (que o Flutter também expõe como rótulo de
  semântica/TalkBack); o único sem era o toggle de mostrar/ocultar senha em
  `LyTextField` (`core/design_system/`), usado nas 4 telas de auth
  (login/signup/convite/redefinição). Corrigido com dois parâmetros novos
  — `showPasswordLabel`/`hidePasswordLabel` — porque o design system não
  conhece `AppLocalizations` (não é feature, não tem l10n próprio; quem
  chama já tem `l10n` em mãos) e um `assert` no construtor barra em tempo
  de desenvolvimento qualquer novo uso de `obscure: true` sem os rótulos.
  Chaves novas `commonShowPassword`/`commonHidePassword` nas 3 ARBs
  (pt-PT ganhou "palavra-passe", não "senha" — mesmo critério do resto do
  arquivo). Teste de widget novo em `ly_text_field_test.dart` cobrindo o
  toggle do rótulo ao tocar.
- **Toque ≥48dp: auditado, nenhum achado na área que o Aceite cobre.** Todo
  `IconButton`/`TextButton`/`ListTile` do fluxo Hoje→executar→finalizar
  usa os widgets padrão do Material sem `constraints`/`visualDensity`
  customizados — o mínimo de 48dp é o próprio default do Flutter, não
  precisou de nada novo. **Achado fora do escopo do Aceite, anotado e não
  corrigido:** os links "tentar de novo"/"remover" de uma mensagem que
  falhou no chat (`ChatBubble`, dentro de um `Wrap` com `GestureDetector`
  em cima de só `Text` caption) têm alvo de toque do tamanho do próprio
  texto — bem abaixo de 48dp. Não mexi: aumentar a área de toque sem
  aumentar o texto pede redesenhar a linha de ações da bolha falha (mudaria
  o layout compacto que a P3.5 desenhou de propósito para caber "não
  enviada" + duas ações numa bolha estreita), risco maior que o valor de
  corrigir de passagem numa tarefa de auditoria. Fica pendência.
- **Contraste WCAG AA: auditado nos dois temas com fórmula de luminância
  relativa real (não estimativa).** O tema **dark — o único que o app
  realmente mostra** (`main.dart` força `themeMode: ThemeMode.dark`, sem
  seguir o tema do sistema) passa AA em todo par texto/fundo testado:
  pior caso foi `danger` (vermelho) sobre `surface`, 6,56:1, folgado acima
  do mínimo de 4,5:1 para texto normal. **Achado real, não corrigido:** o
  tema **light** — definido em `LyColors.light` mas inatingível hoje porque
  nada liga `ThemeMode.system`/`.light` — falha AA feio para as cores
  semânticas usadas como *texto* direto (não como badge com fundo tintado):
  `success`/`warning`/`danger`/`info` sobre branco dão 1,92/1,67/2,77/2,54:1,
  todos abaixo até do mínimo de 3:1 para texto grande. Como isso não
  aparece pra nenhum usuário real agora (tema light morto) e mexer na
  paleta sem poder olhar o resultado (nada renderiza light hoje) é decisão
  estrutural de token de cor, não ajuste de auditoria, não toquei em
  `ly_colors.dart` — registrado como dívida técnica para quando (se) o
  tema light for ligado de verdade.
- **TalkBack no fluxo Hoje→executar→finalizar: NÃO verificado em device —
  mesmo bloqueio conhecido desde a P3.4/P3.5/P4.1/P4.2** (`google-services.json`
  ausente barra todo build Android; nem macOS nem iOS têm pasta de
  plataforma gerada nesta máquina). Fiz o que dava sem device: auditoria
  estática do widget tree do fluxo (Hoje → `SetRow`/timer de descanso →
  resumo do fim de treino) — todo campo tem `label`/`labelText`, todo botão
  de ícone tem `tooltip`, nenhum `Icon` solto carrega significado sem texto
  ao lado, e o único uso de `Semantics` explícito no app (`AgendaDayCell`,
  da P4.1) já está correto. Isso reduz o risco, mas **não substitui** ouvir
  o TalkBack de verdade — item novo na tabela de pendências do STATUS.md.
- **Verificado:** `flutter analyze` limpo (0 issues), guard de strings
  limpo, `dart run tool/check_arb_parity.dart` verde (350 chaves — as 348
  + as 2 novas de senha), **67 testes verdes** (2 novos: `set_row_test.dart`
  corrigido para `42,5` e o teste novo do toggle de senha). Nenhum serviço
  Go tocado nesta tarefa (auditoria é 100% app).

### P4.4 (2026-11-07, Mac) — parcial: a tarefa NÃO fecha

Feita só a parte que não depende de humano. Checkbox segue aberto e o total
do STATUS segue 28/31.

- **Varredura (passo 3).** `flutter analyze`: 104 erros, **todos** em
  `app/build/ios/SourcePackages/` (artefato do build iOS no simulador, fora do
  git); em `lib/` e `test/` zero. Corrigido excluindo `build/**` em
  `analysis_options.yaml`: agora **0 issues**. `flutter test`: **67 verdes**.
  `check_arb_parity`: OK, 350 chaves nos 3 idiomas. `go vet` limpo e
  `go test` verde nos 4 serviços (identity 2 pacotes, workout 3,
  assessment 3, comms 6; todos ok).
- **Secrets.** Nenhum `.env` real, chave, keystore ou token versionado; só
  `.env.example` com defaults de dev (`minioadmin`, `dev-internal-token`) e
  campos sensíveis vazios. `key.properties`, `*.jks` e `*.keystore` já estão
  no `.gitignore` do `android/`. `google-services.json` é versionado por
  decisão (ADR-014, não é segredo). **Achado:** o buildType `release` do
  Android ainda assina com a chave debug (`TODO` em
  `android/app/build.gradle.kts`): precisa do keystore antes do appbundle.
- **LGPD mínima (ADR-008): AUSENTE.** Não existe tabela/endpoint de
  consentimento (`consents`) no `identity`, nem etapa de consentimento na tela
  de aceite do convite, nem fluxo de exclusão de conta (nenhum
  `DELETE /v1/me` ou equivalente no identity/workout/assessment/comms; nada no
  app). Conforme o plano, **não implementado nesta rodada**: vira tarefa que
  **bloqueia o release** (sugestão: P4.5, full-stack em 5 serviços, com
  exclusão física de saúde/fotos e anonimização das execuções, mais teste de
  exclusão como feature de primeira classe).
- **Build web.** `flutter build web --release` (canvaskit; wasm segue
  inviável, ver P4.2) passou: `build/web` 42 MB (inclui `canvaskit/` local),
  `main.dart.js` 1,19 MB gzip. Versão do app: `1.0.0+1`.
- **Roteiro E2E.** [e2e-final.md](e2e-final.md) escrito (roteiro + checklist
  de smoke por plataforma). **Nenhuma execução completa**: depende dos
  bloqueios humanos abaixo.
- **Não feito por bloqueio humano (não contornado):** appbundle assinado
  (sem `google-services.json`, o build Android inteiro falha; sem keystore),
  iOS archive (sem conta/assinatura Apple), convite com Resend real e
  staging, push em Android/iOS (AVD sem Play Store, sem
  `GoogleService-Info.plist`/APNs).

#### Pendências classificadas

**Bloqueia release**
1. LGPD: consentimento no aceite do convite + exclusão de conta (ADR-008). Tarefa nova.
2. `google-services.json` ausente: build Android falha (STATUS #1). Ação humana.
3. Keystore de release Android (hoje assina com debug) e appbundle.
4. iOS: conta/assinatura Apple, `GoogleService-Info.plist`, APNs, archive.
5. Resend com chave real + staging para o passo do convite.
6. Push em device real e deep link (STATUS #2, #3, #4; depende de #2 e AVD com Play Services).
7. Cold start Android medido (STATUS #6, meta 2,5 s).
8. TalkBack real no fluxo Hoje→executar→finalizar (STATUS #7, Aceite literal da P4.3).
9. Aba Agenda com dados reais (STATUS #5): dá para fazer no Chrome/iOS agora.
10. Executar o E2E final nas 3 plataformas (Aceite da P4.4).
11. Crash handler: não há `runZonedGuarded`/`FlutterError.onError` nem destino de log (nota da P4.2). Precisa de decisão (ADR) sobre o destino; o mínimo para release é capturar e logar localmente, e o ideal é um backend de erros.
12. ~~Rate limit no lookup de e-mail entre tenants (login/forgot, dívida do P0.4): exposição pública no release.~~ **Resolvido em 2026-11-07** — ver "Limite de tentativas" abaixo.

**Limite de tentativas (2026-11-07, Mac — fecha a dívida do P0.4 / ADR-002 §2c)**
- `identity/internal/ratelimit`: `Store` com `RedisStore` (INCR+PEXPIRE num
  script Lua, atômico) e `MemoryStore` (dev/teste, `REDIS_URL` vazio).
  `go-redis v9.22.0`, mesma versão do comms. `APP_ENV=production` sem
  `REDIS_URL` não sobe.
- Middleware por rota, janela e bloqueio de **5 min** (`RateLimitCooldown`):
  login 5 falhas por e-mail / 30 por IP (login certo zera o e-mail);
  forgot-password 3 por e-mail / 10 por IP (conta todo pedido); reset-password
  e aceite de convite 10 falhas por IP; signup 10 por IP. Resposta
  `429 too_many_requests` + `Retry-After` + `params.retry_after_seconds`.
  E-mail entra na chave só como hash. Redis fora = libera e loga (login no ar
  vale mais que o limite). Limite por IP folgado: academia sai por um IP só.
- **Enumeração fechada:** o login confere a senha antes de devolver
  `409 multiple_tenants`, e a lista só traz as academias onde a senha bateu;
  senha certa em uma só entra direto. E-mail sem conta gasta o mesmo argon2
  (tempo de resposta não denuncia).
- `TRUST_PROXY=true` só atrás de proxy reverso (IP = último do
  `X-Forwarded-For`) — **ligar no deploy**, senão todo mundo divide o IP do proxy.
- App: `errorTooManyRequests` em 3 idiomas ("aguarde N minutos"). CI sobe
  Redis também para o identity (`TestRedisStoreCooldown`).

**Vai pro 2.0**
- ~~Vínculo coach↔aluno no identity~~ → virou a **P4.7** (ADR-016, decisão de 2026-11-07: o ADR-008 §3 é do MVP). Seguem para o 2.0: `created_by` fora das tabelas e o push de "treino pendente" a todos os tenants.
- Timezone por tenant; locale dinâmico do conteúdo (conteúdo dinâmico ignora o idioma da tela).
- Contraste: tokens semânticos de cor usados como texto abaixo de 4,5:1 no tema dark (P4.3).
- Alvos de toque abaixo de 48 dp em itens já anotados na P4.3.
- Lighthouse mobile com throttling 4G/CPU e build `--wasm` (depende de `flutter_secure_storage_web`).
- Paginação do Check-ins/alunos acima de 200 por papel; header da lista de alunos em janela muito baixa (P1.8).
- Testes de widget dos skeletons/retry (P4.2); fila offline persistente na web (hoje memória).
- Verificação do `docker compose` e Android/Windows do P0 (Toolchain Windows).

### P4.5 (2026-11-07, Mac)

LGPD mínima do ADR-008 (§1, §2, §6) ponta a ponta. Backend em
`a7ff105`, app em `43b7b2d`.

- **Finalidades.** `terms` (aceite dos termos e da política, todo papel),
  `health_data` (obrigatória do aluno) e `progress_photos` (opcional). O
  `terms` é uma finalidade a mais que o plano não listava: sem uma linha em
  `consents` o aceite dos termos do coach/owner não teria onde ser registrado
  (§3 exige o aceite no signup). O gate exige `terms` de todos e `health_data`
  do aluno.
- **identity.** Migrations `0010_consents` (tabela append-only, RLS, índice por
  `tenant_id`, índice único parcial `revoked_at IS NULL`) e
  `0011_user_deletion_status` (`deleting`/`deleted` no CHECK de `users.status`).
  `GET/PUT /v1/me/consents` (PUT devolve também um access token já com as
  claims novas); claims do JWT ganharam `consents` (só as vigentes na
  `TERMS_VERSION` atual, então termo novo derruba tudo e cai no gate); respostas
  de signup/login/refresh/accept trazem `consents`, `needs_consent` e
  `terms_version`. `POST /v1/tenants` e `POST /v1/invitations/accept` exigem
  `terms_version` (400 `consent_required`, 409 `terms_version_mismatch`), e o
  aceite do aluno exige `health_data: true`. `DELETE /v1/me` (senha) →
  `deleting` + refresh tokens revogados → `DELETE /internal/v1/users/{id}` nos 3
  serviços (todos são tentados; falha vira 502 `erasure_failed` com a lista) →
  anonimização (e-mail `deleted+<id>@deleted.invalid`, nome `deleted`, hash
  vazio, papéis/tokens/resets/convites do e-mail apagados). Owner recebe 403
  `owner_cannot_delete`; senha errada, 403 `invalid_password` (não 401, que o
  app trata como sessão morta). `GET /internal/v1/users/{id}/consents` (M2M) existe
  para o assessment. Usuários `deleting`/`deleted` somem da lista do professor e
  não renovam sessão (o refresh agora exige `active`; antes `disabled` ainda
  renovava). Código novo: `internal/erasure` (cliente M2M, duplicável),
  `SessionIssuer` (substitui `issueTokens`). Variáveis novas: `TERMS_VERSION`,
  `WORKOUT_URL`, `ASSESSMENT_URL`, `COMMS_URL`.
- **assessment.** `DELETE /internal/v1/users/{id}`: apaga medidas,
  bioimpedância e fotos **e todos os objetos da pasta do aluno no storage**
  (lista pelo prefixo `tenants/{t}/students/{s}/`, então pega até upload que
  nunca virou linha); objetos primeiro, banco depois, para a repetição sempre
  achar o que falta. Foto: o aluno age pelas claims (`progress_photos` vigente;
  presign e cadastro dão 403 `consent_required`), mas o **coach age sobre OUTRA
  pessoa**, e as claims dele não dizem nada do aluno — por isso o assessment
  ganhou um cliente M2M do identity (`IDENTITY_URL`, `internal/consent`) usado
  só nas rotas do coach: sem consentimento, a lista de fotos vem vazia com
  `consent_revoked: true`, presign/cadastro dão 403 e o `photo_count` do resumo
  zera. Falha ao consultar o identity é 500 (na dúvida, não grava foto).
- **workout.** Execuções: `student_id` vira o UUID nulo (os logs de série são
  append-only e nem são tocados). Estado de rotação: excluído. **Desvio do
  plano:** planos atribuídos são **desatribuídos** (student_id nulo, título
  limpo), não deletados — a versão publicada é imutável (ADR-004 §1, trigger no
  banco) e as sessões anonimizadas ainda referenciam o snapshot dela.
- **comms.** Mensagens: autor vira UUID nulo (a conversa permanece para o outro
  participante); check-ins: aluno/revisor nulos e `pain_notes`/`comment`
  apagados (texto livre de saúde); `device_tokens` e `notification_log`
  excluídos.
- **app.** Termos em `assets/legal/` (`terms_*`/`privacy_*` × pt-BR, pt-PT, en;
  versão `2026-11-v1` dentro de cada texto, conferida por teste contra
  `AppConfig.termsVersion` = `--dart-define=TERMS_VERSION`). Signup com
  checkbox dos termos; aceite de convite com `ConsentChoices` (termos +
  `health_data` + `progress_photos`); `/consent` é o gate (o router prende o
  usuário lá enquanto `AuthState.consentPending`); `/account` (ícone no app bar
  dos dois shells) com interruptor das fotos, documentos, sair e "Excluir minha
  conta" (senha); ao concluir limpa o banco local do treino, os rascunhos de
  check-in e a sessão. **Não existia tela de perfil nem botão de sair**: a tela
  Conta nasceu aqui e é o primeiro logout visível do app.
- **Verificado à mão** contra o backend local (4 serviços reiniciados com o
  código novo, MinIO real): signup sem termos 400; aceite sem `health_data` 400;
  foto subida no MinIO por URL assinada e cadastrada; revogar fotos → presign
  403 com o token novo, coach vê lista vazia com `consent_revoked`, contagem 0;
  reconceder volta a mostrar; owner 403; senha errada 403; com o assessment
  parado o DELETE deu 502 `erasure_failed` ["assessment"], usuário ficou
  `deleting`, login bloqueado, workout e comms já tinham apagado; repetir com o
  assessment de volta deu 204. Depois: fotos e medidas 0, **pasta do aluno
  ausente no MinIO**, mensagem do aluno anônima e a do coach intacta, check-in
  anônimo sem textos, device excluído, plano desatribuído, usuário `deleted`
  com e-mail/nome/hash anonimizados, consentimentos mantidos, login falha.

**Dívidas e limites anotados**
- **Sem reconciliação.** Se a exclusão parar em 502 e o access token (15 min)
  expirar, o usuário fica `deleting` sem como repetir (login bloqueado). Hoje
  só dá para concluir à mão (reenviar `DELETE /internal/v1/users/{id}` aos 3
  serviços e anonimizar). Um job que varre `deleting` antigos resolve; não
  coube no MVP.
- Access token do usuário excluído segue válido até 15 min: um sync offline
  tardio pode recriar uma sessão sob o UUID dele. Mesma janela vale para
  revogar fotos nos serviços que só leem claims (o app troca o token no PUT, mas
  outro device só vê a mudança no próximo refresh).
- O link de convite não revela o papel, então o aceite pede `health_data` a todo
  convidado (coach incluso); o servidor só grava as finalidades de saúde de
  aluno. Um `GET` público do papel do convite resolveria.
- Imagens do chat do usuário excluído continuam no storage do comms
  (anonimizadas só no autor); apagar objeto exige presigner com delete no comms.
- O coach não ganhou aviso na UI para `consent_revoked` (a ficha mostra o
  estado vazio de fotos). Texto do estado vazio específico fica para depois.
- **Revisão jurídica dos textos de `assets/legal/` pendente (humano):** o
  conteúdo é razoável para o MVP, mas foi escrito sem advogado; o contato
  `privacidade@lyfta.app` e a identificação do controlador precisam ser
  confirmados antes do release.
- Migrations só rodam com superusuário/dono: com `DATABASE_URL` da role
  `lyfta_app` o `migrate` falha no `TRUNCATE schema_migrations`. Usei
  `postgres://postgres@localhost:5432/<banco>` (trust local).
- Nenhuma dependência nova (Go e Flutter); só `assets:` no `pubspec.yaml`.
- `dart format` no repo inteiro **não** é o estilo do projeto (reformata ~70
  arquivos); formatar só arquivo novo.

### P4.6 (2026-11-07, Mac)

- **Versões pinadas:** `sentry_flutter 10.3.0` (exata no `pubspec.yaml`; traz
  `sentry 10.3.0`) e `github.com/getsentry/sentry-go v0.50.0` nos 4 serviços
  (Go 1.26.4; a série `1.0.0-alpha` foi ignorada). O `go get` subiu
  `golang.org/x/sync`, `x/sys` e `x/text` como transitivas. Registrado em
  `backend/README.md` § Stack pinada.
- **Go, duplicado por serviço (ADR-013):** `internal/obs` (`Init` +
  `ScrubEvent`/`ScrubBreadcrumb`) e `internal/http/sentry.go`
  (`SentryScope`, `Recover`, `ReportServerErrors`, `setSentryUser`). O
  `Recover` saiu do `middleware.go` para o `sentry.go`; mesma resposta de antes
  (500 `internal_error`) e agora reporta o panic. Ordem no router:
  `RequestID → SentryScope → StructuredLogging → Recover →
  ReportServerErrors`. `RequireAuth` põe `user_id` (sub) e `tenant_id` no
  escopo da requisição. `SENTRY_DSN`/`SENTRY_RELEASE` no `config`, `APP_ENV`
  vira o `environment`; flush de 2 s no shutdown.
- **Privacidade:** `SendDefaultPII` falso; `ScrubEvent` deixa só `user.id` e a
  rota sem query (método + URL), tira corpo, headers, cookies, env; breadcrumbs
  perdem query/headers/corpo. No Flutter o filtro também limpa e-mail, query
  string e `Bearer` de mensagens de exceção, e desliga screenshot, view
  hierarchy, captura de request falho e breadcrumb de toque em widget.
- **Desvio/limite (5xx):** o evento de 5xx leva rota (padrão do chi, não o path
  com ids), `request_id`, `user_id`/`tenant_id` e a mensagem
  `http Internal Server Error: GET /rota` — não o erro que causou. A causa está
  no log estruturado do mesmo `request_id` (os handlers já logam). Capturar o
  erro de dentro do handler exigiria mexer em todos os `writeError`. O texto do
  valor de um panic vai no evento (só e-mail/query são filtrados no Flutter; no
  Go o valor do panic não é reescrito) — não colocar dado pessoal em `panic()`.
- **Flutter:** `core/observability/error_reporting.dart`; `main.dart` chama
  `ErrorReporting.run(_start)`. DSN vazio: zona guardada + `FlutterError.onError`
  + `PlatformDispatcher.onError` só escrevem no console (`debugPrint`). DSN
  presente: `SentryFlutter.init(appRunner:)`. Variáveis `SENTRY_DSN`,
  `SENTRY_ENVIRONMENT` (padrão `development`) e `APP_RELEASE` (padrão
  `1.0.0+1`; manter igual ao `version:` do pubspec ao virar release).
  `setSession` (id+tenant) é chamado na raiz quando o usuário muda.
- **Testes:** Go, por serviço, `obs_test` (Init sem DSN é no-op; filtro remove
  PII via cliente com transporte falso) e `http/sentry_test` (panic vira 500 JSON
  sem derrubar o processo, com e sem cliente Sentry; panic gera 1 evento, 5xx
  gera 1 com `request_id`, 4xx/2xx nenhum). Flutter: 8 testes (DSN vazio, travas
  de `configure`, filtro de user/request/mensagem/exceção/breadcrumb, zona
  guardada captura erro assíncrono, de framework e de plataforma).
- **Pendente (humano):** criar o projeto Sentry/GlitchTip, preencher
  `SENTRY_DSN` (serviços) e `--dart-define=SENTRY_DSN` (app) e conferir um
  evento real chegando sem PII. Fecha também o item "crash handler sem destino
  de log" da P4.4.

### P4.7 (2026-11-07, Mac)

Vínculo professor↔aluno do ADR-016 (ADR-008 §3) ponta a ponta. Backend em
`9e4d66f`, app no commit seguinte.

- **identity.** Migration `0012_coach_students` (RLS, índice
  `(tenant_id, coach_id)`, `down` reversível) com o backfill pedido: o primeiro
  `invited_by` do e-mail se for coach|owner ativo, senão o owner ativo mais
  antigo; rodou contra o banco de dev (167 alunos vinculados; os 9 sem vínculo
  são fixtures de teste de tenant sem owner). `POST /v1/invitations` de aluno
  cria usuário e vínculo na mesma transação (`UserRepo.CreateStudent`).
  `DELETE /v1/me`: `MarkDeleting` já devolve os alunos do coach ao owner ativo
  mais antigo (na mesma transação do status) e `Anonymize` apaga a linha do
  aluno. `GET /v1/users`: owner vê todos, com `coach_id`/`coach_name`, e filtra
  por `?coach_id=`; coach sem owner recebe só os alunos dele.
  `PUT /v1/students/{id}/coach` (só owner; 422 `validation_error` para aluno/
  coach inválido) e M2M `GET /internal/v1/coaches/{id}/students` e
  `/students/{id}/coach` (404 `student_not_found` sem vínculo).
- **coachlink** duplicado em workout, assessment e comms (cache de 30 s por
  tenant+coach, `COACH_LINK_CACHE_TTL`, TTL 0 desliga; falha do identity vira
  erro e **não é cacheada**). `CoachOf` só no comms, sem cache. `IDENTITY_URL`
  nova no workout e no comms (`.env.example`, README do backend).
- **workout.** `RequireStudentLink` em `/students/{id}/...`; `GET /plans/{id}`,
  `PUT .../draft` e `POST .../publish` checam `plan.StudentID`; `authorizeWrite`
  saiu (agora é o vínculo, então o coach reatribuído edita); `POST /plans` checa
  o aluno e o `coach_id` do owner precisa ser o vinculado (400
  `validation_error`).
- **assessment.** Middleware no `Route("/students/{id}")`, antes do
  consentimento. **comms.** `Start`, conversa (`authorizeParticipant`: o coach
  da conversa precisa ser o atual do aluno; o aluno e o owner não dependem),
  presign, lista de conversas (omite ex-alunos), `GET /checkins` (sem
  `student_id` filtra por `ANY(conjunto)` via `ListForStudents`), `Review` e o
  push de dor forte só para o `CoachOf`.
- **app.** `AuthState.isOwner`; o tile do aluno mostra "Professor: X" e a ação
  "Trocar professor" (bottom sheet com coaches/owners ativos) só para o owner;
  `student_not_found` traduzido nas 3 ARBs e sem botão de tentar de novo em
  evolução (4 abas + resumo), check-ins e chat.
- **Testes.** identity: lista escopada, reatribuição, M2M, exclusão de coach e
  de aluno, isolamento cross-tenant e backfill (como superusuário,
  `SUPERUSER_DATABASE_URL`, que o CI agora exporta). Por serviço, um teste
  cross-coach com identity fake sobre o cliente `coachlink` real: coach B recebe
  404 `student_not_found`, owner acessa, reatribuição troca quem acessa,
  identity fora do ar dá 500. coachlink: cache, TTL, falha, owner sem chamada.
  Flutter: tile como owner e como coach, `student_not_found` sem retry.
- **Desvios/decisões.** (1) `GET /v1/users?role=coach|owner` segue aberto ao
  coach comum: é o diretório de nomes que o chat (`participantDirectory`) usa e
  não é dado de aluno; só a lista de alunos (ou sem filtro) é escopada.
  (2) `OverrideDay` com `student_id` de outro aluno (`/me/plan/override-day`)
  também checa o vínculo; o plano não listava. (3) Exclusão de coach devolve os
  alunos no `MarkDeleting` e não só no `Anonymize`: se o erase de algum serviço
  falhar, os alunos já ficaram com o owner. (4) Após reatribuir, o coach novo
  abre uma conversa nova (a unique é por par aluno+coach); o aluno passa a ter
  duas conversas e o app já cai na lista quando há mais de uma.
- **Pendências.** O cache de 30 s é por instância: reatribuição leva até 30 s
  para valer. Os binários dos 4 serviços que estavam rodando em dev são
  anteriores a esta tarefa — reiniciar com o código novo (a migration 0012 já
  está aplicada no banco local). Fora de escopo seguem N:N, histórico de
  vínculos, escolher o coach no convite e arquivar a conversa do ex-coach.

