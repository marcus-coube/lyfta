# STATUS — MVP 2.5

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P12.2`. Decisões D1–D7 confirmadas; nenhuma tarefa travada.

| Fase | Progresso | Situação |
|---|---|---|
| P9 — Prescrição (cluster, rótulo, variações) | 4/4 | fechada (2026-11-13) |
| P10 — Player do aluno | 2/2 | fechada (2026-11-13) |
| P11 — Check-in do professor | 2/2 | fechada (2026-11-13) |
| P12 — Mídia de execução e release | 1/4 | em andamento |
| **Total** | **9/12** | |

## Decisões (detalhe no [README](README.md#decisões-a-confirmar-antes-da-tarefa-indicada))

| # | Assunto | Trava | Situação |
|---|---|---|---|
| D1 | Modelagem do cluster | P9.1 | ✅ recomendada, confirmada em 2026-11-13 |
| D2 | Rótulo livre × lista fixa | P9.1 | ✅ recomendada, confirmada em 2026-11-13 |
| D3 | "Voltar" sem desfazer série | P10.2 | ✅ recomendada, confirmada em 2026-11-13 |
| D4 | Compressão de vídeo (`video_compress`) | P12.2 | ✅ recomendada, confirmada em 2026-11-13 |
| D5 | Teto de 30 dias sem visualização | P12.1 | ✅ recomendada, confirmada em 2026-11-13 |
| D6 | Consentimento via `progress_photos` | P12.1 | ✅ recomendada, confirmada em 2026-11-13 |
| D7 | Resposta do professor pelo chat | P12.1 | ✅ recomendada, confirmada em 2026-11-13 |

## Bancos locais

Nenhum banco novo. Migrations novas: workout `0021`, `0022`; comms `0008`.

## Log de marcos

| Data | Evento |
|---|---|
| 2026-11-13 | Plano do 2.5 criado a partir da validação com o cliente (12 tarefas, P9–P12); ADR-019 e ADR-020 propostos |
| 2026-11-13 | Usuário confirmou D1–D7 nas opções recomendadas; ADR-019 e ADR-020 **aceitos** |
| 2026-11-13 | P9.1 pronta: migration workout `0021` (cluster + `prescribed_sets.label`), domínio, handler, repo e snapshot |
| 2026-11-13 | P9.2 pronta: migration workout `0022` (`set_variations` + `prescribed_sets.variation_id`), CRUD `/v1/variations`, validação no `SaveDraft`, variação no plano, no Hoje e no snapshot |
| 2026-11-13 | P9.3 pronta: builder com cluster, rótulo e variação por série (chips, menu ⋮), `tempo` em round-trip e tela Variações na aba Biblioteca |
| 2026-11-13 | P9.4 pronta (P9 fechada): chips de rótulo e variação com (i) na série do player (`LyChip` no design system), `sessionBlockCluster`; cluster conduzido como dropset |
| 2026-11-13 | P10.1 pronta: replicar carga para as outras séries (estado dos campos em `ExerciseFields`, só tela, sem evento nem fila) |
| 2026-11-13 | P10.2 pronta (P10 fechada): cronômetro geral `h:mm:ss`, métricas únicas em `domain/session_metrics.dart` (séries, reps, volume, duração), modal "Treino concluído" na última série (sem descanso, Voltar mantém a sessão) |
| 2026-11-13 | P11.1 pronta: `POST /v1/students/{id}/sessions/lookup` e `GET /v1/students/{id}/sessions/{client_id}` no workout, métricas numa função só (`domain.MeasureSession`) que também alimenta o resumo do aluno (`reps_total`, `duration_seconds`) |
| 2026-11-13 | P11.2 pronta (P11 fechada): card do check-in com treino e métricas (lookup por página), detalhe `/students/:id/sessions/:clientId` com prescrito × feito, série corrigida/não feita, tabela ≥ 840 px |
| 2026-11-16 | P12.1 pronta: migration comms `0008_session_media`, API da mídia de execução (presign 20 MB, registro com HEAD, limite de 3 por sessão, ciência do professor com 7 dias e feedback pelo chat), job de expiração com o advisory lock do comms e relógio injetável, exclusão de conta com objetos, `unacked_media` nas stats; `TERMS_VERSION` 2026-11-v3 |
