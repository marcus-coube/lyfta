# ADR-004 — Treino: template vs execução (snapshot)

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

O doc 009 modela Workout → Day → Exercise → Set. Sem separação entre o *plano* que o
coach edita e o *histórico* do aluno, editar um template reescreveria o passado.

## Decisão

Dois agregados distintos:

1. **Template (mutável, versionado):**
   `workout_plans` → `workout_days` → `workout_blocks` → `block_exercises` → `prescribed_sets`.
   - `workout_blocks` é o agrupamento que representa superset/circuito/drop set
     (`block_type: straight | superset | dropset | rest_pause | circuit`). Um exercício
     "normal" é um bloco de um exercício só.
   - Prescrição por set: reps (ou faixa), carga alvo (absoluta, %1RM ou RPE/RIR),
     cadência, descanso.
   - Editar um plano publica uma **nova versão** (`workout_plan_versions`); versões
     antigas são imutáveis.

2. **Execução (imutável, append-only — ver ADR-003):**
   `workout_sessions` → `workout_set_logs`.
   - Ao iniciar uma sessão, o app **congela um snapshot** da versão do plano
     (`workout_sessions.plan_version_id` + cópia desnormalizada dos dados exibidos).
   - O histórico do aluno referencia o snapshot, nunca o template vivo.

3. **Rotação A→B→C:** estado por aluno (`student_plan_state`: plano ativo, próximo dia,
   última execução), com override manual pelo aluno/coach. A rotação avança quando a
   sessão é concluída (regra: sessão com ≥1 set registrado conta como concluída;
   configurável depois).

## Consequências

- Coach edita livremente sem corromper histórico; comparação de progresso usa
  `exercise_id` como eixo estável entre versões.
- "Carga anterior" (feature central) = último `workout_set_log` do aluno para o mesmo
  `exercise_id`, independente do plano — consulta simples e estável.
- Custo: mais tabelas e o conceito de versão desde o início; aceito por ser o núcleo do produto.
