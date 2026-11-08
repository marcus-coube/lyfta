# ADR-018 — Modelos de treino: atribuição por cópia, sem vínculo vivo

**Status:** Aceito
**Data:** 2026-11-08

## Contexto

O builder do 1.0 cria planos sempre presos a um aluno (`workout_plans.student_id
NOT NULL`). O builder completo do 2.0 precisa de **modelos**: um plano montado
uma vez e aplicado a vários alunos. Há duas formas: o plano do aluno referencia
o modelo (editar o modelo muda todos) ou o modelo é copiado na atribuição.

## Decisão

1. **Modelo é um `workout_plan` com `kind = 'template'`** e `student_id NULL`
   (`kind = 'assigned'` exige `student_id`; CHECK no banco). Usa as mesmas
   tabelas e o mesmo ciclo rascunho → publicar do [ADR-004](ADR-004-template-vs-execucao.md).
2. **Atribuir = cópia profunda** da última versão publicada do modelo para um
   plano novo do aluno (dias, blocos, exercícios, séries). O plano copiado
   guarda `source_template_id` só como procedência; **não há vínculo vivo**:
   editar o modelo não altera nenhum aluno, e editar o plano do aluno não altera
   o modelo.
3. **Escopo:** modelo é do tenant. Todo coach do tenant lista e aplica; só o
   autor (`coach_id`) ou o owner edita e arquiva.
4. Modelo nunca entra em `student_plan_state`, nunca é executado e nunca
   aparece em `/me/*`.

## Consequências

- Personalizar o treino de um aluno depois de aplicar um modelo é o caso comum e
  não tem efeito colateral.
- Propagar uma correção do modelo é **manual**: "reaplicar" lista quem recebeu
  o modelo (pelo `source_template_id`) e o coach escolhe os alunos. Para cada
  um, o rascunho do plano é substituído pela versão atual do modelo e
  publicado como versão nova (ADR-004): o histórico fica, mas os ajustes
  individuais daquele plano se perdem, e o app avisa disso. Confirmado pelo
  usuário em 2026-11-08.
- **Alternativa rejeitada:** referência viva com "override" por aluno. Exigiria
  merge de árvores versionadas e quebraria a leitura simples do ADR-004.
