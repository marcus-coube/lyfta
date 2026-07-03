# ADR-003 — Offline: escopo e estratégia de sincronização

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

"Offline-friendly workout execution" é requisito de produto. Sincronização offline
genérica (qualquer entidade, qualquer direção) é a maior fonte de complexidade e bugs
possível no app. É preciso limitar o escopo e escolher um modelo que minimize conflitos.

## Decisão

1. **Escopo offline do MVP: somente execução de treino.** O aluno consegue abrir o
   treino do dia (previamente baixado), executar séries, registrar cargas e descanso
   sem rede. Todo o resto do app exige conexão.
2. **Execução é append-only.** Cada série executada (`workout_set_logs`) é um fato
   imutável criado apenas pelo próprio aluno, com `client_id` (UUID gerado no device)
   como chave de idempotência. Fatos imutáveis de escritor único não geram conflito
   de merge — o sync vira uma fila de push simples com retry.
3. **Storage local:** SQLite (via Drift) no Flutter, espelhando apenas as tabelas
   necessárias: treino ativo do aluno (snapshot, ver ADR-004), histórico recente de
   cargas, fila de eventos pendentes.
4. **Protocolo de sync:**
   - *Push:* fila local de eventos → `POST /v1/sync/workout-logs` em lote, idempotente
     por `client_id`; o servidor responde quais foram aceitos.
   - *Pull:* leitura incremental por cursor `updated_at`/`sync_token` para treinos e
     biblioteca de exercícios do aluno.
5. Correção de um registro errado não edita o fato: gera um evento de revisão
   (`revises: <client_id>`), preservando o modelo append-only.

## Consequências

- Elimina resolução de conflitos bidirecional; não há "merge" a implementar.
- O coach não edita execuções; se precisar anotar, é outro tipo de dado (comentário).
- Relógio do device não é confiável: o servidor grava `received_at` e o evento carrega
  `performed_at` do device; relatórios usam `performed_at` com sanidade validada.
- Ampliar o escopo offline (ex.: chat) exige novo ADR — não é um caminho "de graça".
