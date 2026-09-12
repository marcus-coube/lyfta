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

## - [ ] P4.2 Performance e robustez ("app leve, sem travar")

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
