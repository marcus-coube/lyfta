# ADR-006 — Backend: monolito modular em Go com eventos via outbox

**Status:** Superado por [ADR-013](ADR-013-microservicos-db-por-servico.md) (2026-07-03)
**Data:** 2026-07-02

## Contexto

O doc 001 define "modular monolith" e lista os módulos (auth, tenant, users, workout,
running, finance, chat, notification), mas não define fronteiras nem comunicação.

## Decisão

1. **Um único binário Go**, módulos como packages de domínio:
   `internal/<modulo>/{domain,service,repo,http}`.
2. **Regra de dependência:** um módulo não importa código interno de outro. Comunicação
   síncrona só via interfaces públicas declaradas em `internal/<modulo>/api.go`
   (verificado por lint de imports, ex.: go-arch-lint/depguard).
3. **Efeitos colaterais entre módulos são assíncronos, via outbox:**
   - Na mesma transação da escrita de negócio, o módulo insere um evento em
     `outbox_events (id, tenant_id, type, payload jsonb, created_at, processed_at)`.
   - Um dispatcher (goroutine no próprio binário) consome a outbox e entrega aos
     handlers inscritos (notificação, chat, badge, etc.). At-least-once: handlers idempotentes.
   - Exemplos: `workout.plan_published` → notificação "novo treino";
     `finance.invoice_overdue` → lembrete de pagamento.
4. **Jobs agendados** (rotação de faturas, lembretes): scheduler no próprio binário
   (ex.: cron interno) usando lock no Postgres — sem infraestrutura extra.
5. Redis fica restrito a: cache, pub/sub para fan-out de WebSocket, rate limit.
   **Nada de fila de negócio em Redis** — a fonte de verdade de eventos é a outbox no Postgres.

## Consequências

- Deploy de um artefato só no VPS (ADR-009); sem broker de mensagens para operar.
- A outbox cria o "sistema nervoso" do produto (notificações, integrações futuras)
  sem acoplamento direto entre módulos.
- Se um dia for necessário extrair um módulo para serviço, as fronteiras já existem.

## Alternativas consideradas

- **Microserviços:** custo operacional injustificável para dev solo. Rejeitado.
- **Chamadas diretas entre módulos para efeitos colaterais:** acoplamento e perda de
  eventos em falha parcial. Rejeitado.
