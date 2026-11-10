# P6 — Builder completo

Meta da fase: o coach monta uma vez e aplica a muitos (modelos), gerencia os
planos de cada aluno e edita sem atrito; o aluno executa superset e circuito do
jeito que foram prescritos.

O que o 1.0 já entregou e **não** é refeito aqui: versões com rascunho →
publicar (P1.4), blocos tipados (`straight|superset|dropset|rest_pause|circuit`),
prescrição estruturada por série, rotação A→B→C automática e troca de dia pelo
aluno (P1.5).

Refs normativas: ADR-003, ADR-004, ADR-016, ADR-018.

---

## - [x] P6.1 Modelos de treino (workout)

**Objetivo:** biblioteca de modelos do tenant, aplicada por cópia (ADR-018).
**Passos:**
1. Migration: `workout_plans.kind` (`assigned|template`, default `assigned`),
   `student_id` nullable com CHECK (`kind='assigned'` ⇔ `student_id IS NOT
   NULL`), `source_template_id UUID NULL`, `description TEXT`. Índice
   `(tenant_id, kind, updated_at DESC)`.
2. `GET /v1/templates` (busca por título, cursor), `POST /v1/templates`; o
   resto reusa as rotas de plano (`GET /v1/plans/{id}`, `PUT .../draft`,
   `POST .../publish`), que passam a aceitar `kind=template` — editar só autor
   ou owner (403 `template_not_owned`). `POST /v1/templates/{id}/archive`.
3. `POST /v1/templates/{id}/assign` `{student_ids[], publish: bool}`: cópia
   profunda da última versão publicada para um plano novo de cada aluno, numa
   transação por aluno; resposta lista sucesso/erro por aluno (aluno fora do
   vínculo = `student_not_found` naquele item, não falha o lote). Com
   `publish=true` o plano entra direto na rotação do aluno.
4. Reaplicar: `GET /v1/templates/{id}/recipients` (planos com esse
   `source_template_id`: aluno, versão do modelo aplicada, se o plano foi
   editado depois) e `POST /v1/templates/{id}/reapply` `{plan_ids[]}`: troca a
   árvore de cada plano pela última versão publicada do modelo e publica uma
   versão nova (rotação reancora pelo rótulo, como no P1.8). Resultado por item.
5. `POST /v1/plans/{id}/save-as-template` (copia a versão publicada ou o
   rascunho atual).
6. Garantir que modelo nunca aparece em `/me/*`, no histórico nem no
   `student_plan_state`.
**Aceite:** aplicar um modelo a 3 alunos cria 3 planos independentes (editar o
modelo depois não muda nenhum — teste); modelo sem versão publicada = 422
`template_not_published`; reaplicar gera versão nova só nos planos escolhidos;
teste de handler do assign com um aluno fora do vínculo.

## - [ ] P6.2 Planos do aluno: duplicar, arquivar, ativar, versões, próximo dia (workout)

**Objetivo:** o coach administra o ciclo de vida dos planos de cada aluno.
**Passos:**
1. `POST /v1/plans/{id}/duplicate` `{student_id?}` (mesmo aluno ou outro do
   vínculo; nasce como rascunho).
2. `POST /v1/plans/{id}/archive` e `POST /v1/students/{id}/plans/{plan_id}/activate`
   (troca o plano ativo em `student_plan_state`; rotação recomeça no 1º dia).
   Arquivar o plano ativo exige ativar outro antes (409 `plan_is_active`).
3. `GET /v1/plans/{id}/versions` (número, `published_at`, autor, contagem de
   dias/exercícios) — o `?version=N` do P1.4 já serve o conteúdo.
4. `PUT /v1/students/{id}/plan/next-day` `{day_id}`: override do próximo dia
   pelo coach (o do aluno já existe), refletido no `/me/today` e no pull.
5. `GET /v1/students/{id}/plans` ganha `kind`, `status`, `is_active`,
   `source_template_id`.
**Aceite:** ativar outro plano troca o treino do dia do aluno no próximo pull;
override do coach aparece no `/me/today`; histórico de execuções do plano
arquivado continua no gráfico de carga (ADR-004 §2); testes de handler.

## - [ ] P6.3 App — modelos e atribuição em lote (Flutter)

**Objetivo:** fluxo "monta uma vez, aplica a muitos".
**Passos:**
1. Aba **Modelos** no shell do coach: lista com busca, criar, editar no mesmo
   builder da P1.6 (modo modelo: sem aluno, título + descrição), arquivar.
2. "Aplicar a alunos": seleção múltipla com busca (P5.2), opção publicar já ou
   como rascunho, resultado por aluno.
   "Reaplicar a quem recebeu": lista da P6.1 com quem já está na versão atual e
   quem teve o plano editado depois (destacado), seleção, aviso de que os
   ajustes individuais serão substituídos e resultado por aluno.
3. No builder de um plano: "Salvar como modelo"; na aba Treino da ficha
   (P5.4): "Aplicar modelo", "Duplicar", "Arquivar", "Ativar", com o plano
   ativo destacado.
**Aceite:** coach cria modelo, aplica a 2 alunos e cada um vê o treino no Hoje;
teste de widget da seleção múltipla e do resultado parcial.

## - [ ] P6.4 App — ergonomia do builder (Flutter)

**Objetivo:** montar um treino de 6 dias sem repetição manual.
**Passos:**
1. Reordenar por arrastar dias, blocos e exercícios (`ReorderableListView`,
   sem dependência nova); duplicar dia e duplicar bloco.
2. Séries: "copiar para as próximas" e "adicionar série igual à anterior";
   descanso padrão do bloco aplicado às séries novas.
3. Histórico de versões read-only (lista da P6.2 + abrir versão N) e banner
   "alterações não publicadas" no rascunho.
4. Banner de lesões ativas do aluno no topo do builder (P5.3), recolhível.
5. Override do próximo dia pelo coach na aba Treino da ficha.
**Aceite:** reordenar e publicar mantém a ordem no Hoje do aluno; teste de
widget do reordenar e do "copiar para as próximas".

## - [ ] P6.5 App — player por bloco (Flutter)

**Objetivo:** o aluno executa o bloco como foi prescrito. Hoje o player é uma
lista plana de exercícios e o bloco é só um rótulo.
**Passos:**
1. `superset` e `circuit`: o player agrupa o bloco num cartão e conduz por
   **rodada** (série 1 do exercício A → série 1 do B → … → descanso do bloco
   `workout_blocks.rest_seconds` → rodada 2). Sem descanso entre exercícios da
   mesma rodada, salvo o `rest_seconds` da série.
2. `dropset` e `rest_pause`: séries encadeadas no mesmo cartão com o descanso
   curto da prescrição; rótulo explica o método (i18n).
3. Contrato offline **inalterado** (ADR-003): os eventos continuam por série
   (`exercise_id` + `set_no`), só a ordem de condução muda. Pular exercício e
   corrigir série seguem funcionando dentro do bloco.
4. Lógica de condução numa classe pura (`BlockRunner`) testável sem widget.
**Aceite:** superset A/B com 3 séries conduz A1→B1→descanso→A2→B2→…; circuito
de 3 exercícios × 2 rodadas idem; testes unitários do `BlockRunner` e um teste
de widget do cartão de superset; treino straight continua idêntico ao 1.0.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

### P6.1 — modelos de treino (workout)

- **Migration `0019_plan_templates`** (aplicada up/down 1/up no banco local). Além
  das colunas do plano (`kind`, `description`, `source_template_id`,
  `student_id` nullable + CHECK `(kind='assigned') = (student_id IS NOT NULL)`,
  índice `(tenant_id, kind, updated_at DESC, id DESC)`), ganhou duas colunas de
  procedência que o plano não previa mas o "Reaplicar a quem recebeu" (P6.3)
  precisa: `source_version_no` (versão do modelo que gerou o conteúdo) e
  `edited_after_source` (o coach mexeu depois; `SaveDraft` marca, aplicar e
  reaplicar zeram). O `down` **recusa** rodar se existirem modelos (versão
  publicada é imutável por trigger; apagar modelo é decisão humana).
- **Rotas** (todas sob `RequireRole(owner, coach)`): `GET/POST /v1/templates`,
  `POST /v1/templates/{id}/archive|unarchive|assign|reapply`, `GET .../recipients`,
  `POST /v1/plans/{id}/save-as-template`. Ler/editar/publicar a árvore do
  modelo reusa `GET /v1/plans/{id}`, `PUT .../draft`, `POST .../publish`
  (`authorizePlan`: modelo = qualquer coach lê; só autor/owner escreve, 403
  `template_not_owned`; arquivado = 409 `template_archived`). `PUT .../draft`
  aceita `description` (só vale em modelo). Id de plano de aluno nas rotas
  `/templates/{id}/...` = 404 `not_found` (e vice-versa em save-as-template).
- **Refator no repo** (sem mudar contrato do 1.0): `ReplaceDraft` virou
  `SaveDraft(DraftInput)` (ReplaceDraft segue como atalho); `insertTreeTx`,
  `replaceDraftTreeTx`, `publishDraftTx` e `versionTreeTx` são as peças
  transacionais que assign/reapply/save-as-template compõem — uma transação por
  plano de aluno. Publicar modelo só congela a versão (sem rotação,
  `student_plan_state` nem arquivar planos). `SaveDraft` agora sempre bumpa
  `updated_at` (antes só com título).
- **Assign** lê a árvore publicada uma vez e copia para cada aluno; item fora do
  vínculo = `student_not_found` naquele item; lote máx. 50, ids deduplicados;
  resposta 200 com `items[{student_id, plan_id, ok, error{code,params}}]`.
  `publish=false` → plano em rascunho v1 fora da rotação. O `coach_id` da cópia é
  o professor vinculado ao aluno (decisão 3 abaixo).
- **Reapply** substitui o rascunho do plano (inclusive um rascunho aberto com
  ajustes) pela árvore do modelo e publica versão nova; erros por item:
  `plan_not_from_template` (422), `plan_archived` (409, plano arquivado/
  substituído não é reaplicado para não reativar sem o coach pedir),
  `student_not_found` (vínculo), `not_found`. Como publicar sempre ativa o
  plano, reaplicar num plano só-rascunho o põe na rotação.
- **Listagem** `GET /v1/templates?q=&status=&cursor=&limit=`: busca sem acento
  (`lyfta_search_norm`), keyset `(updated_at, id)`, default só ativos
  (`status=archived|all` amplia), com `days_count`/`exercises_count` da última
  versão publicada e `assigned_count`. `recipients` devolve também
  `template_version_no` (o app compara com `source_version_no`) e filtra pelo
  vínculo do coach; planos de alunos já excluídos (titular anônimo) ficam fora.
- **Contrato mexido já agora (P6.2 item 5 adiantado):** `GET /students/{id}/plans`
  ganhou `kind` e `source_template_id` (`status`/`is_active` já existiam);
  `planResponse` ganhou `kind`, `description`, `source_*`, `edited_after_source`
  e `student_id` vira omitido no modelo.
- **Decisões do usuário (2026-11-10, aplicadas):**
  1. `save-as-template` copia a versão **mais recente** do plano (rascunho aberto,
     senão a última publicada — o que o builder mostra); o modelo nasce em
     **rascunho**, sem procedência, e o coach publica antes de atribuir.
  2. **Desarquivar:** `POST /v1/templates/{id}/unarchive`, mesma permissão do
     archive (autor ou owner; 403 `template_not_owned`). Idempotente como o
     archive (já ativo = 200, sem erro — padrão único nas duas rotas). Volta como
     `published` se o modelo já teve versão publicada, senão `draft`.
  3. **`coach_id` do plano criado = professor vinculado ao aluno** (ADR-016), não
     quem atribuiu. Coach que passou no vínculo já é esse professor (sem
     chamada); para o owner consulta-se `GET /internal/v1/students/{id}/coach`;
     aluno sem professor vinculado fica com quem atribuiu (fallback: o plano
     precisa de um autor e o owner é o responsável pela academia). O
     `POST /v1/plans` segue a mesma regra e o campo `coach_id` do corpo foi
     **removido** (o único valor aceito era justamente o professor vinculado,
     então virou redundante; o app não o enviava).
  4. **Existência do aluno validada no identity** (M2M em lote
     `POST /internal/v1/students/statuses`, via `ExistingStudents` no
     `internal/coachlink` do workout) em `assign` (por item) e no `POST /v1/plans`:
     inexistente, de outro tenant ou excluído = 404 `student_not_found`. Aluno
     **`inactive` recebe plano** — o coach pode preparar a volta dele (o job de
     treino pendente do comms já ignora inativos, então não dispara lembrete).
     Efeito colateral: criar plano passa a depender do identity também para o
     owner (identity fora do ar = 500, falha fechada).
- **Reapply (decisões mantidas):** `plan_archived` por item para plano
  arquivado/substituído (reativaria sem o coach pedir) e publicar ativa o plano
  (reaplicar num plano só-rascunho o põe na rotação).
