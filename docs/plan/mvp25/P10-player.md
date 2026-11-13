# P10 — Player do aluno

Meta da fase: menos digitação e um fim de treino claro. Só app; **nenhuma
mudança de backend nem de contrato offline** (ADR-003).

O que já existe: `SetRow` com reps/carga pré-preenchidos (carga anterior ou
alvo), `SessionController.logSet/finish`, resumo (`session_summary_sheet.dart`:
séries, volume, duração em minutos), `LocalSessionRows.startedAt/finishedAt` e
`workout_sessions.started_at/finished_at` no servidor.

Refs normativas: ADR-003.

---

## - [x] P10.1 Replicar carga para as outras séries (Flutter)

**Objetivo:** digitar a carga uma vez por exercício.
**Passos:**
1. Quando o aluno **altera** o campo de carga de uma série e existe outra série
   **ainda não registrada** do mesmo exercício com carga diferente, aparece sob
   a linha a ação "Replicar para as outras séries" (uma vez por exercício por
   sessão; some ao ser usada ou dispensada).
2. Toque → diálogo "Replicar X kg para todas as séries de {exercício}?" →
   confirmar preenche o **campo** de carga das demais séries pendentes daquele
   exercício. Não toca em reps, em série já registrada (corrigir é revisão),
   nem em outros exercícios do bloco.
3. Só estado de tela: nenhum evento, nada na fila. Valor replicado passa pela
   mesma validação (`SetInput`, 0–1.000) ao registrar.
4. O estado dos campos precisa subir do `SetRow` (hoje cada linha é dona dos
   seus controllers) para quem enxerga o exercício — `_ExerciseCard` e
   `block_card.dart`, onde as séries do mesmo exercício ficam em rodadas
   diferentes. Exercício repetido no dia (`setNoOffset`) conta como exercícios
   separados.
**Aceite:** em exercício de 4 séries, digitar 40 na 1ª e confirmar deixa 40 nas
4; com a 1ª já registrada, digitar na 2ª replica só para 3ª e 4ª; em bi-set,
replicar no exercício A não mexe no B; teste de widget dos três casos.

## - [x] P10.2 Cronômetro geral e modal de treino concluído (Flutter)

**Objetivo:** o aluno vê o tempo de treino e é levado ao fim quando termina.
**Decisão:** D3.
**Passos:**
1. **Cronômetro:** tempo decorrido desde `session.startedAt` no topo do player
   (`h:mm:ss`), sempre visível, derivado do relógio (sobrevive a fechar e
   reabrir o app; sem pausa). `Timer.periodic` de 1 s só na tela, sem
   reconstruir a lista de exercícios a cada tique. Semântica/acessibilidade no
   padrão do timer de descanso.
2. **Métricas finais (definição única, `domain/session_metrics.dart`):**
   séries = logs efetivos; reps = Σ `reps_done`; volume = Σ `load × reps`;
   duração = `finishedAt − startedAt`. O resumo passa a mostrar as quatro,
   duração como `h:mm:ss` (hoje minutos) e o nome do treino (rótulo do dia).
   A P11 calcula o mesmo no servidor.
3. **Treino concluído:** ao registrar a série que deixa **todas** as séries do
   dia com log, não inicia descanso e abre o modal "Treino concluído" com as
   métricas parciais e duas ações: **Finalizar treino** (o fluxo de hoje:
   `finish()` → resumo → check-in) e **Voltar** (fecha o modal, sessão segue
   aberta e o cronômetro correndo). Depois do "Voltar" o modal não reabre
   sozinho; o botão "Finalizar" da AppBar fica em destaque. Corrigir uma série
   não reabre o modal.
4. O "Finalizar" manual da AppBar (com séries pendentes) continua como está.
5. Strings novas nas 3 ARBs.
**Aceite:** registrar a última série abre o modal sem timer de descanso;
"Voltar" permite corrigir a série e finalizar pela AppBar; fechar e reabrir o
app no meio do treino mantém o cronômetro coerente; resumo mostra séries, reps,
volume e duração iguais ao que a P11.1 devolve para a mesma sessão; teste
unitário das métricas (com revisão de série) e de widget do modal (abre na
última série, não reabre após voltar).

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

- **P10.1:** o estado da carga subiu do `SetRow` para `ExerciseFields`
  (`presentation/exercise_fields.dart`, um `ChangeNotifier` por exercício do
  dia, chave `exerciseId:setNoOffset`), guardado num `ExerciseFieldsRegistry`
  no `_SessionBodyState` do player. `_ExerciseCard` e `BlockCard` passam o
  `fields` do exercício a cada `SetRow` (em bi-set as séries de A ficam em
  rodadas diferentes mas dividem o mesmo objeto). `SetRow.fields` é opcional:
  sem ele a linha segue dona do controller. Efeito colateral bom: o que foi
  digitado sobrevive à lista descartar o cartão fora da tela.
- **P10.2:** `domain/session_metrics.dart` é a definição única das métricas
  (`SessionMetrics.of` ignora o log apontado por `revises`, então aceita lista
  crua ou já revisada; `formatClock` dá `h:mm:ss`). `SessionState.metrics()` e
  `allSetsLogged` (toda série prescrita de `today.runs` tem log; dia sem série
  nunca completa) saem dele; `elapsed`/`totalVolumeKg` foram removidos.
  `finishSession` agora devolve o `finishedAt` gravado no `session_finish` e
  `finish()` devolve o estado com ele, para o resumo medir a duração exata.
  Cronômetro: `_SessionClock` (Timer de 1 s e `setState` só nele, irmão da
  lista no `Column`; `Semantics` com rótulo fixo e valor, sem live region).
  Modal: a tela do player faz `ref.listen` e abre o diálogo na **transição**
  "faltava série -> todas com log"; revisão troca o log sem criar outro, e
  "Voltar" não precisa de flag. Os cartões (`_ExerciseCard`, `BlockCard`) só
  deixam de iniciar o descanso quando `allSetsLogged`. Com tudo registrado o
  "Finalizar" da AppBar vira `FilledButton`. O fluxo de fim foi extraído para
  `_finish` (modal e AppBar compartilham). Resumo e modal usam
  `SessionMetricsGrid` (séries, reps, volume, duração) e mostram o rótulo do
  dia. Sessão reaberta já completa não abre o modal (sem transição).
  Dívida: o cronômetro lê `DateTime.now()`; o teste espera 1,1 s reais.
