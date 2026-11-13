# P11 — Check-in do professor com o treino

Meta da fase: o check-in deixa de ser só nota e comentário — o professor vê
qual treino foi feito, as métricas (as mesmas do resumo do aluno) e, ao abrir,
exercícios e cargas.

O que já existe: `workout_checkins` no comms guarda `session_client_id`
(= `workout_sessions.client_id`); `CoachCheckinsTab` por aluno (ficha e
Evolução). **Não existe** rota para o coach ler uma sessão do aluno;
`SessionRepo.SessionSnapshot()` existe sem rota.

O app compõe: check-ins vêm do comms, a sessão vem do workout (ADR-013 — sem
chamada serviço→serviço para isso).

Refs normativas: ADR-003, ADR-004, ADR-013, ADR-016.

---

## - [x] P11.1 Sessão do aluno para o coach (workout)

**Objetivo:** resumo em lote e detalhe de sessão, por `client_id`.
**Passos:**
1. `POST /v1/students/{id}/sessions/lookup` `{client_ids[]}` (máx. 50,
   deduplicado) → `items[{client_id, day_label, plan_title, started_at,
   finished_at, duration_seconds, sets_count, reps_total, volume_kg}]`. Sessão
   que ainda não chegou ao servidor (fila offline do aluno) simplesmente não
   vem na lista.
2. `GET /v1/students/{id}/sessions/{client_id}` → o resumo acima +
   `blocks[{block_type, exercises[{exercise_id, name, sets[{set_no, label,
   variation_name, prescribed{reps_min, reps_max, target_*}, done{reps_done,
   load_kg, rpe, performed_at, revised}}]}]}]`. Prescrito vem do **snapshot**
   da sessão (ADR-004), feito vem dos logs **efetivos** (última revisão vence —
   reusar `effectiveLogFilter`); série sem log vem com `done: null`. 404
   `session_not_found`.
3. Métricas com a definição da P10.2; `duration_seconds` nulo sem
   `finished_at`, e nulo também se negativo ou > 12 h (relógio do device não é
   confiável, ADR-003).
4. Papéis owner/coach, middleware de vínculo da rota `/v1/students/{id}`;
   sessão de outro aluno = 404. Nome do exercício no idioma da tela
   (`Accept-Language`, P8.3).
5. `sessionSummaryDTO` do aluno (`/v1/me/sessions`, `recent_sessions`) ganha
   `reps_total` e `duration_seconds` com a mesma função — uma definição só.
**Aceite:** sessão com uma série corrigida devolve o valor corrigido e
`revised: true`; lookup com um `client_id` inexistente devolve só os demais;
coach fora do vínculo = 404 `student_not_found`; números batem com o resumo da
P10.2 para a mesma sessão; testes de handler (feliz, vínculo, não encontrada)
e de repo (revisão, sessão sem finish).

## - [ ] P11.2 App — check-in com métricas e detalhe do treino (Flutter)

**Objetivo:** o professor avalia o check-in olhando o treino.
**Passos:**
1. `CoachCheckinsTab`: depois de cada página de check-ins, um `lookup` com os
   `session_client_id` da página. O card ganha uma linha do treino: rótulo do
   dia + título do plano, e séries · reps · volume · duração. Sem sessão no
   servidor: "Treino ainda não sincronizado" (i18n), sem erro. Falha do lookup
   não derruba a lista (o card fica sem a linha, com retry).
2. Toque no card abre o detalhe (`/students/:id/sessions/:clientId`): cabeçalho
   com as métricas e as respostas do check-in; lista por bloco/exercício com
   prescrito × feito por série, chips de rótulo e variação (P9), marca de série
   corrigida e de série não feita. Somente leitura. Acima de 840 px, tabela;
   abaixo, coluna única.
3. "Marcar revisado" disponível também no detalhe.
4. Reusar o formatador de prescrição do player (`prescription_format.dart`) e
   o de métricas da P10.2.
**Aceite:** aluno treina e faz check-in; o professor vê no card o treino e os
mesmos números do resumo do aluno, abre e vê exercícios e cargas; check-in de
sessão ainda não sincronizada aparece sem a linha do treino e ganha a linha
depois do sync; teste de widget do card (com e sem sessão) e do detalhe.

---

## Notas de execução

**P11.1 (2026-11-13)**
- Rotas no `HistoryHandler` (`internal/http/coach_sessions.go`), dentro de `/v1/students/{id}` (herdam `RequireStudentLink` e o filtro owner/coach): `POST .../sessions/lookup` e `GET .../sessions/{client_id}`. `session_not_found` novo em `apierror.go`.
- Métricas únicas em `domain.MeasureSession` (`internal/domain/session_metrics.go`), espelho do `session_metrics.dart`. O repo (`summarizeSessions`) deixou de somar no SQL: lê as sessões e os logs efetivos (`effectiveLogFilter`) e chama a função — `RecentSessions`, `SessionsInRange`, lookup e detalhe passam por ela. `sessionSummaryDTO` ganhou `reps_total` e `duration_seconds` (só campos novos; o app atual ignora).
- Divergência do app, intencional (spec): duração nula se negativa ou > 12 h; o Dart devolve `Duration.zero` no negativo. Volume ignora log sem carga ou sem reps (igual ao Dart). Volume arredondado a 2 casas.
- Detalhe casa feito × prescrito por (`exercise_id`, `set_no`). Se o mesmo exercício aparecer em dois blocos do dia, as séries de mesmo número dividem o mesmo log — dívida aceita (o player também identifica o log por exercício+série).
- `plan_title` vem do plano da versão da sessão (título atual do plano, não congelado no snapshot).
