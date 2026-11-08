# ADR-017 — Financeiro do 2.0: serviço `billing`, só baixa manual

**Status:** Aceito
**Data:** 2026-11-08 (revisado no mesmo dia, antes de qualquer implementação:
acesso do coach configurável e retenção do titular na exclusão de conta)

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
2. **Recebimento no 2.0 = só `method=manual`.** Quem tem acesso (§3) registra a
   baixa (data, valor, observação). Sem PIX, cartão, Asaas/Stripe, webhook, cobrança
   automática, lembrete de vencimento, pagamento parcial, multa/juros, recibo ou
   nota fiscal. O schema do ADR-007 §4 nasce inteiro (`provider`,
   `provider_ref`, `payment_provider_events`), sem driver: plugar PIX depois é um
   driver novo, não uma migração.
3. **Acesso:** o owner opera todo o financeiro. O personal autônomo é owner da
   própria organização, então vê tudo sem configuração nenhuma. Para o coach,
   cada organização escolhe numa configuração do tenant
   (`tenants.coach_billing_access`, no `identity`):
   - `status_only` (padrão, o caso da academia com coach contratado): o coach
     vê só o selo "inadimplente" dos próprios alunos, sem valores;
   - `own_students`: o coach vê assinaturas e faturas dos próprios alunos
     (ADR-016), cria e altera assinatura deles e dá baixa manual.

   Em qualquer modo, planos de mensalidade, estorno, cancelamento de fatura e
   receita da organização são **só do owner**. O `billing` lê a configuração
   por M2M no `identity` com cache de 30 s, igual ao vínculo do ADR-016. O
   aluno vê as próprias faturas, somente leitura.
4. **Fuso:** os jobs (geração mensal e `open → overdue`) rodam no fuso de cada
   tenant (`tenants.timezone` no `identity`, ADR-007 §3), lido por M2M com
   cache. Uma instância por vez via `pg_try_advisory_lock`.
5. **Exclusão de conta com financeiro** (substitui o ADR-008 §2 para
   registros financeiros: o titular **não** é anonimizado neles):
   - **Bloqueio:** aluno com fatura `open` ou `overdue` não exclui a conta. O
     `DELETE /v1/me` consulta o `billing` antes de qualquer passo e responde
     409 `pending_invoices`. O aluno precisa quitar com o owner primeiro.
   - **Retenção do titular:** o `billing` guarda nome e e-mail do aluno em
     `billing_customers` (cópia tirada ao criar a assinatura e atualizada na
     exclusão). Na exclusão, essa cópia fica, com `account_deleted_at`. Base
     legal: obrigação legal de guarda e exercício regular de direito (LGPD
     art. 7º II e VI, art. 16 I). O restante segue o ADR-008 §2: saúde e fotos
     apagadas, treino e chat anonimizados, usuário anonimizado no `identity`.
   - **Assinatura:** a exclusão cancela a assinatura ativa, para o job não
     gerar fatura de conta excluída.
   - **Exibição:** fatura e histórico de conta excluída mostram nome, e-mail e
     valores, com o selo "conta excluída".
   - O `billing` entra na orquestração do `DELETE /v1/me` (pré-checagem e
     `DELETE /internal/v1/users/{id}`).

## Consequências

- Guardar o e-mail depois da exclusão é o ponto mais fraco da base legal:
  conferir na revisão jurídica (L6 do STATUS do 1.0).
- O 2.0 não cobra sozinho: o owner confere o extrato do banco e dá baixa. É o
  fluxo de quem hoje usa planilha, que é o público inicial.
- Mais um serviço para subir, monitorar (Sentry, ADR-009 §5) e incluir no CI
  (a matrix descobre por `backend/<svc>/go.mod`).
- Este ADR substitui o "PIX/manual" do [ADR-012](ADR-012-escopo-mvp-packs.md) §6
  para o 2.0. PIX entra num pacote futuro, com ADR próprio do driver.
- **Alternativa rejeitada:** financeiro dentro do `identity`. Misturaria
  autenticação com dinheiro e faria o serviço mais crítico crescer com regras
  de negócio que mudam muito.
