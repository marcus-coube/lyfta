# ADR-017 — Financeiro do 2.0: serviço `billing`, só baixa manual

**Status:** Aceito
**Data:** 2026-11-08

## Contexto

O pacote 2.0 (doc 000) traz o financeiro como alavanca de adoção do coach,
descrito como "PIX / manual reconciliation first". O [ADR-007](ADR-007-dinheiro-financeiro.md)
já fixou o modelo (centavos inteiros, Subscription/Invoice/Payment, status
derivado, provider-agnostic). Faltava decidir **onde** o financeiro vive na
arquitetura de serviços do [ADR-013](ADR-013-microservicos-db-por-servico.md) e
**quanto** do recebimento entra no 2.0. Decisão do usuário (2026-11-08): PIX fica
para depois; o 2.0 entrega só a baixa manual.

## Decisão

1. **Sexto serviço, `billing`** (porta 8085, banco `lyfta_billing`), no mesmo
   molde dos outros (chi + pgxpool + slog, `security`/`repo` duplicados, nenhum
   import entre serviços). Dono de `billing_plans`, `subscriptions`, `invoices`,
   `payments` e `payment_provider_events`.
2. **Recebimento no 2.0 = só `method=manual`.** O owner registra a baixa (data,
   valor, observação). Sem PIX, cartão, Asaas/Stripe, webhook, cobrança
   automática, lembrete de vencimento, pagamento parcial, multa/juros, recibo ou
   nota fiscal. O schema do ADR-007 §4 nasce inteiro (`provider`,
   `provider_ref`, `payment_provider_events`), sem driver: plugar PIX depois é um
   driver novo, não uma migração.
3. **Acesso:** financeiro é **só do owner** no 2.0 (planos, assinaturas,
   faturas, baixa, estorno, receita). O coach vê apenas o selo
   "inadimplente" dos próprios alunos (status derivado, sem valores). O aluno vê
   as próprias faturas, somente leitura.
4. **Fuso:** os jobs (geração mensal e `open → overdue`) rodam no fuso de cada
   tenant (`tenants.timezone` no `identity`, ADR-007 §3), lido por M2M com
   cache. Uma instância por vez via `pg_try_advisory_lock`.
5. **LGPD:** registro financeiro é obrigação legal/fiscal e **não** é apagado na
   exclusão de conta (ADR-008 §2). A titularidade some pela anonimização do
   usuário no `identity`; o `billing` guarda só `student_id`, sem nome nem
   e-mail, e por isso não entra na orquestração do `DELETE /v1/me`.

## Consequências

- O 2.0 não cobra sozinho: o owner confere o extrato do banco e dá baixa. É o
  fluxo de quem hoje usa planilha, que é o público inicial.
- Mais um serviço para subir, monitorar (Sentry, ADR-009 §5) e incluir no CI
  (a matrix descobre por `backend/<svc>/go.mod`).
- Este ADR substitui o "PIX/manual" do [ADR-012](ADR-012-escopo-mvp-packs.md) §6
  para o 2.0. PIX entra num pacote futuro, com ADR próprio do driver.
- **Alternativa rejeitada:** financeiro dentro do `identity`. Misturaria
  autenticação com dinheiro e faria o serviço mais crítico crescer com regras
  de negócio que mudam muito.
