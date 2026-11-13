# ADR-019 — Prescrição: cluster set, rótulo e variação por série

**Status:** Aceito (D1 e D2 do [plano do 2.5](../plan/mvp25/README.md) confirmadas em 2026-11-13)
**Data:** 2026-11-13

## Contexto

A validação do 2.0 com o cliente pediu três acréscimos à prescrição do
[ADR-004](ADR-004-template-vs-execucao.md): cluster set como tipo de bloco, um
rótulo opcional por série ("Aquecimento") e uma variação cadastrada por série
(nome + descrição), ambos visíveis ao aluno na execução. O ADR-004 fixa a lista
de `block_type` e o que compõe a prescrição por série.

## Decisão

1. **`block_type` ganha `cluster`** (`straight | superset | dropset |
   rest_pause | circuit | cluster`). Como `dropset` e `rest_pause`, é **só o
   tipo**: cada mini-série é uma série prescrita com descanso curto; o player
   conduz as séries encadeadas e explica o método. Sem campos próprios.
2. **Rótulo:** `prescribed_sets.label`, texto livre curto (até 24), opcional. É
   conteúdo do coach, num idioma só, como `block_exercises.notes`.
3. **Variação:** tabela `set_variations` no `workout`, por tenant (nome,
   descrição, arquivável, sem exclusão física); `prescribed_sets.variation_id`
   opcional. Todo coach do tenant lê e escreve. Sem tabela de tradução.
4. **Snapshot:** rótulo e nome/descrição da variação são **copiados** para o
   `/me/today` e para o snapshot da sessão. Editar ou arquivar a variação não
   altera treino publicado já baixado nem sessão iniciada.
5. **Execução inalterada:** rótulo e variação não entram em `workout_set_logs`
   nem nos eventos do [ADR-003](ADR-003-offline-sync.md); quem precisa deles
   depois lê o snapshot da sessão.

## Consequências

- Cluster de 4 × (2+2+2) vira 12 linhas de série; o builder ameniza com
  "copiar para as próximas". Volume e gráfico de carga seguem corretos sem
  mudança.
- **Alternativa rejeitada (D1):** série = cluster inteiro, com nº de
  mini-séries e pausa intra-série em campos próprios. Mais fiel ao método, mas
  muda prescrição, player e registro só para um tipo de bloco; reavaliar se o
  cliente achar a montagem trabalhosa — e nesse caso tratar dropset e
  rest-pause junto.
- **Alternativa rejeitada (D2):** lista fixa de rótulos traduzidos com cor por
  item. Ganha tradução e cor semântica, perde o texto que o coach quiser.
- Uma versão publicada continua apontando para a variação mesmo arquivada; por
  isso não há `DELETE`.
