# ADR-007 — Financeiro: representação de dinheiro e modelo Invoice/Payment

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

O MVP tem baixa manual de pagamentos; o futuro tem PIX/cartão via Asaas ou Stripe.
Erros de modelagem de dinheiro são caros e difíceis de migrar.

## Decisão

1. **Dinheiro em centavos inteiros** (`amount_cents BIGINT` + `currency CHAR(3)`,
   default `BRL`). Proibido float/decimal para valores monetários em qualquer camada,
   incluindo o Flutter.
2. **Cobrança ≠ recebimento:**
   - `subscriptions`: vínculo aluno↔plano de mensalidade (valor, dia de vencimento, status).
   - `invoices`: fatura gerada por job mensal a partir da subscription
     (`open | paid | overdue | canceled`), imutável após paga.
   - `payments`: registro de recebimento ligado à invoice
     (`method: manual | pix | card | ...`, `provider`, `provider_ref`, `paid_at`).
     A baixa manual do MVP é um `payment` com `method=manual`.
3. **Status do aluno é derivado, nunca editado à mão:** inadimplente = existe invoice
   `overdue`; a transição `open → overdue` é feita por job diário no fuso do tenant
   (`tenants.timezone`, default `America/Sao_Paulo`).
4. **Provider-agnostic desde já:** o campo `provider`/`provider_ref` e uma tabela
   `payment_provider_events` (webhooks crus) já existem no schema, mesmo com só o
   método manual implementado — plugar Asaas depois não muda o modelo.
5. Correções contábeis não apagam nada: estorno = novo registro (`payments.reversed_by`).

## Consequências

- Fluxo de caixa e relatórios saem por consulta sobre invoices/payments, sem estado duplicado.
- A integração futura com PIX/Asaas é um novo "driver" de payment, não uma migração.
