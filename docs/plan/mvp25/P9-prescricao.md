# P9 — Prescrição: cluster, rótulo e variações

Meta da fase: o coach prescreve cluster set, marca séries com um rótulo
("Aquecimento") e com uma variação cadastrada; o aluno vê os dois como chips na
série durante o treino, com a descrição da variação a um toque.

O que já existe e **não** é refeito: blocos tipados
(`straight|superset|dropset|rest_pause|circuit`), `BlockRunner` e cartão de
bloco (P6.5), editor de séries (P1.6/P6.4).

Refs normativas: ADR-004, ADR-018, [ADR-019](../../adr/ADR-019-prescricao-cluster-rotulo-variacao.md).

---

## - [x] P9.1 Cluster e rótulo por série (workout)

**Objetivo:** servidor aceita `cluster` e `label` e os entrega ao aluno.
**Decisões:** D1, D2.
**Passos:**
1. Migration `0021_cluster_set_label`: troca o CHECK de
   `workout_blocks.block_type` (hoje inline e sem nome na 0006 — confirmar o
   nome gerado antes do `DROP CONSTRAINT`) para incluir `cluster`;
   `prescribed_sets.label TEXT NULL` com CHECK `char_length(label) BETWEEN 1 AND 24`.
   O `down` recusa rodar se existir bloco `cluster`.
2. `domain/plan.go`: `BlockTypeCluster`, `IsValidBlockType`, `PrescribedSet.Label *string`.
3. `http/plans.go`: `setDTO.label`, `parseSet` (trim; vazio = null; > 24 = 422
   no padrão dos outros campos); `plan_view.go` (`daysToDTO`).
4. `repo/plans.go`: os três pontos que tocam `prescribed_sets`
   (`AddPrescribedSet`, `versionTreeTx`, `insertTreeTx`) — isso cobre salvar
   rascunho, aplicar/reaplicar modelo, duplicar e salvar como modelo.
5. `repo/sessions.go` `daySnapshotQuery`: `label` por série no snapshot.
6. **Bug achado no levantamento, corrigir aqui:** o servidor guarda
   `prescribed_sets.tempo`, mas o `PrescribedSet` do app não modela o campo;
   como o `PUT .../draft` substitui a árvore, a cadência some a cada salvamento.
   Lado servidor não muda; registrar para a P9.3 (o app passa a devolver o campo).
**Aceite:** rascunho com bloco `cluster` e série rotulada publica, aparece em
`GET /v1/plans/{id}`, em `/v1/me/today` e no snapshot da sessão; aplicar modelo
copia rótulo; `block_type` desconhecido segue 422; testes de handler (feliz +
rótulo de 25 caracteres) e de repo do snapshot.

## - [ ] P9.2 Variações (workout)

**Objetivo:** cadastro de variações do tenant e vínculo por série.
**Passos:**
1. Migration `0022_set_variations`: tabela `set_variations` (`id`, `tenant_id`,
   `name TEXT` 1–40, `description TEXT` até 1.000, `archived_at`, `created_by`,
   `created_at`, `updated_at`), RLS no padrão do serviço, índice
   `(tenant_id, archived_at, name)`, unicidade de nome por tenant entre as
   ativas (`lower(name)`, parcial `WHERE archived_at IS NULL`).
   `prescribed_sets.variation_id UUID NULL REFERENCES set_variations(id)`.
2. CRUD no molde de `billing_plans` (handler + repo):
   `GET /v1/variations?q=&status=active|archived|all`, `POST /v1/variations`,
   `PUT /v1/variations/{id}`, `POST /v1/variations/{id}/archive|unarchive`.
   Papéis: owner e coach leem e escrevem (conteúdo do tenant, sem autor dono).
   Sem `DELETE`: variação referenciada por versão publicada só arquiva. Nome
   repetido = 409 `variation_name_taken`.
3. Prescrição: `setDTO.variation_id` na escrita; `parseSet`/`SaveDraft` validam
   que existe no tenant e **não está arquivada** quando a série é nova ou mudou
   de variação (422 `variation_not_found`); série que já apontava para uma
   variação depois arquivada continua salvando.
4. Leitura: `GET /v1/plans/{id}` devolve por série
   `variation: {id, name, description}` (join). `/v1/me/today` e
   `daySnapshotQuery` devolvem `variation: {name, description}` **copiados**
   (regra do snapshot do README) — o aluno nunca chama `/v1/variations`.
5. Cópias de árvore (aplicar/reaplicar modelo, duplicar, salvar como modelo)
   carregam `variation_id` (mesmo tenant, mesma linha).
**Aceite:** CRUD com teste de isolamento cross-tenant; série com variação chega
ao `/me/today` com nome e descrição; editar o nome da variação **não** altera o
snapshot de uma sessão já iniciada (teste); arquivada some do `status=active` e
não entra em série nova; testes de handler (feliz + nome duplicado).

## - [ ] P9.3 App — builder: cluster, rótulo, variação e tela Variações (Flutter)

**Objetivo:** o coach cadastra variações e prescreve os três recursos.
**Passos:**
1. `shared/domain/plan.dart`: `BlockType.cluster` (`fromCode`, `code`;
   `isRounds` = false); `PrescribedSet` ganha `label`, `variation`
   (`{id, name, description}`) e **`tempo`** (round-trip do campo que hoje se
   perde — sem UI nova para ele). `fromJson`/`toJson`/`copy`.
2. `plan_l10n.dart` (`blockTypeLabel`) e chaves `builderBlockCluster*` nas 3 ARBs.
   O dropdown do builder já itera `BlockType.values`.
3. `set_editor.dart`: no menu ⋮ da linha (onde estão "copiar para as próximas"
   e "remover" — a linha de 296 px não comporta mais ícones), "Rótulo…" e
   "Variação…". Rótulo: diálogo com campo livre (24) e sugestões em chips
   (Aquecimento, Reconhecimento, Top set, Back-off — i18n; o valor gravado é o
   texto). Variação: seletor com busca sobre `/v1/variations` + "Nenhuma" +
   atalho "Nova variação". Os dois aparecem como chips abaixo da linha da
   série; "copiar para as próximas" **não** copia rótulo (aquecimento é da
   primeira), copia variação.
4. Tela **Variações**: dentro da aba Biblioteca do coach, como segmento
   "Exercícios | Variações" (o shell já tem 6 abas). Lista com busca, criar e
   editar em diálogo (nome + descrição, molde do `template_form_dialog.dart`,
   diálogo dono dos controllers), arquivar/desarquivar, filtro de arquivadas.
   `features/variations/` (`data`, `domain`, `presentation`).
5. Modo leitura (plano arquivado, versão antiga): chips visíveis, sem menu.
**Aceite:** coach cria a variação "Pausa no fundo", monta um cluster com a 1ª
série rotulada "Aquecimento" e a 2ª com a variação, publica; recarregar o
builder mostra tudo, inclusive `tempo` preservado num plano que já o tinha;
testes de widget do `set_editor` (rótulo, variação, copiar para as próximas) e
da tela Variações (criar, nome duplicado vira mensagem i18n).

## - [ ] P9.4 App — player: cluster e chips na série (Flutter)

**Objetivo:** o aluno vê rótulo e variação na série e executa cluster.
**Passos:**
1. Parse de `label` e `variation` no payload do `/me/today` (`domain/today.dart`).
   Vive dentro do JSON do `TodayCache`: **sem** migration do drift.
2. `set_row.dart`: faixa de chips sob a linha da série — rótulo (um token de cor
   do design system) e variação (outro token) com botão (i). O (i) abre modal:
   título = nome, corpo = descrição; sem descrição, o chip não tem (i). Funciona
   offline (dado copiado). Chip novo, se necessário, entra como componente
   `Ly*` no design system; alvo de toque de 48 dp no (i).
3. `block_runner.dart`: `cluster` conduzido como `dropset`/`rest_pause`
   (exercício a exercício, séries encadeadas, descanso `série ?? bloco`).
   `block_card.dart`: rótulo e explicação do método (`sessionBlockCluster*`,
   3 ARBs). `session_player_screen.dart` e `today_screen.dart` já tratam
   "não-straight" de forma genérica — conferir.
4. Tela Hoje: prévia do exercício mostra o rótulo/variação se a lista de séries
   já é exibida ali; senão, nada muda.
**Aceite:** treino publicado na P9.3 aparece no player com o chip "Aquecimento"
na 1ª série e o chip da variação com (i) abrindo o modal, **também com a rede
cortada**; cluster conduz as mini-séries em sequência com o descanso curto;
testes unitários do `BlockRunner` para `cluster` e de widget do `SetRow` com
chips e modal; treino straight sem rótulo fica idêntico ao 2.0.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

**P9.1 (2026-11-13)**
- CHECK de `block_type` confirmado no banco: `workout_blocks_block_type_check`
  (nome gerado). A 0021 troca por constraint de mesmo nome; o rótulo ganhou
  `prescribed_sets_label_len`. `down` recusa rodar com bloco `cluster`
  (testado: up → down → up).
- Rótulo inválido (> 24 caracteres, contados em runas) responde **400**
  `validation_error` com `params.field = ...label`, o padrão de todos os campos
  do builder (o plano diz "422"; 422 aqui é só `unknown_exercise`). Vazio ou só
  espaços vira `null`.
- Os pontos de gravação eram dois `INSERT` (`AddPrescribedSet`, `insertTreeTx`);
  `versionTreeTx` é a leitura e também ganhou `label`. Aplicar modelo, duplicar
  e salvar como modelo passam por leitura + `insertTreeTx`.
- Passo 6 (tempo), **para a P9.3**: o servidor já grava/devolve `tempo`; o
  `PrescribedSet` do app precisa modelar o campo e devolvê-lo no `PUT .../draft`
  (hoje a cadência se perde a cada salvamento). Nada mudou no servidor.
