# ADR-001 — Estratégia de Multi-tenancy

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

O Lyfta atende muitos tenants pequenos (personals, studios, academias). As opções eram:
banco por tenant, schema por tenant, ou banco único com discriminador de tenant.

## Decisão

**Banco PostgreSQL único, com coluna `tenant_id` em toda tabela de dados de negócio,
reforçado por Row-Level Security (RLS) do Postgres.**

Regras normativas:

1. Toda tabela de domínio tem `tenant_id UUID NOT NULL REFERENCES tenants(id)`.
2. Toda tabela de domínio tem política de RLS ativa; a aplicação define
   `SET LOCAL app.tenant_id = '<uuid>'` no início de cada transação.
3. Todo índice composto começa por `tenant_id` (ex.: `(tenant_id, student_id, created_at)`).
4. Nenhuma query de negócio pode omitir o filtro de tenant — o RLS é a rede de
   segurança, não o mecanismo primário; o repositório da aplicação filtra explicitamente.
5. Tabelas globais (sem tenant): `tenants`, `plans`, `feature_flags` (definições),
   `exercises` da biblioteca global (ver ADR-010).
6. Testes de integração obrigatórios de isolamento: usuário do tenant A nunca lê dados do tenant B.

## Consequências

- Operação simples (um banco, um backup, uma migration) — adequado a dev solo em VPS único (ADR-009).
- Isolamento lógico, não físico: um bug de RLS/filtro é vazamento entre clientes — por isso a regra dupla (filtro explícito + RLS).
- Migração futura de um tenant grande para banco dedicado continua possível (dump por `tenant_id`).

## Alternativas consideradas

- **Schema por tenant:** migrations multiplicadas por N tenants, ferramentas de ORM/migração sofrem. Rejeitado.
- **Banco por tenant:** custo operacional inviável para centenas de tenants pequenos. Rejeitado.
