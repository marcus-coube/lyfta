# STATUS — MVP 2.5

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** `P9.2`. Decisões D1–D7 confirmadas; nenhuma tarefa travada.

| Fase | Progresso | Situação |
|---|---|---|
| P9 — Prescrição (cluster, rótulo, variações) | 1/4 | em andamento (P9.1 pronta) |
| P10 — Player do aluno | 0/2 | não iniciada |
| P11 — Check-in do professor | 0/2 | não iniciada |
| P12 — Mídia de execução e release | 0/4 | não iniciada |
| **Total** | **1/12** | |

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
