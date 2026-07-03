# ADR-002 — Identidade: conta por tenant

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

Um usuário pode ter vínculo com mais de um tenant (aluno numa academia e cliente de um
personal). As opções eram conta global (um login, tabela de memberships) ou conta por tenant.

## Decisão

**Conta por tenant.** Cada usuário pertence a exatamente um tenant
(`users.tenant_id NOT NULL`). Papéis (Owner/Admin/Coach/Reception/Student) são
atributos do usuário dentro do seu tenant — um mesmo usuário pode acumular papéis
no mesmo tenant (ex.: coach que também treina).

Regras normativas:

1. E-mail é único **por tenant** (`UNIQUE (tenant_id, email)`), não globalmente.
2. O fluxo de login precisa identificar o tenant antes de autenticar. Ordem de resolução:
   a) deep link / subdomínio do tenant, se presente;
   b) lookup por e-mail: se o e-mail existe em um único tenant, login direto;
   c) se existe em vários, tela de escolha ("Em qual academia?").
3. Claims do JWT: `sub` (user_id), `tid` (tenant_id), `roles` (lista). Sem claim de
   tenant não há acesso a rota de negócio.
4. Convites: aluno entra num tenant via convite do coach/admin (e-mail ou link), criando
   uma conta nova naquele tenant mesmo que o e-mail já exista em outro.

## Consequências

- Modelo e RBAC mais simples: tudo é escopado pelo tenant, sem tabela de memberships.
- **Tradeoff aceito:** a pessoa vinculada a dois tenants tem dois logins e dois históricos
  que não se fundem. Migração futura para conta global é custosa (dedupe de identidade) —
  decisão consciente, revisar apenas se a fusão de histórico virar demanda real de mercado.
- O passo 2b/2c exige um endpoint público de resolução de e-mail→tenants que não pode
  vazar informação (retornar apenas nomes de tenants onde o e-mail existe, com rate limit).

## Alternativas consideradas

- **Conta global + memberships:** mais flexível, um login para tudo; rejeitada pela
  complexidade adicional de troca de tenant, claims e permissões por membership.
