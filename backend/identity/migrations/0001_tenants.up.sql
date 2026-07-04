-- Tabela global (sem tenant_id): tenants (ADR-001 §5).
-- Ids são UUID v7 gerados pela aplicação (Postgres 17 local não tem uuidv7()
-- nativo, que só chega na v18).
CREATE TABLE tenants (
    id         UUID PRIMARY KEY,
    name       TEXT NOT NULL,
    slug       TEXT NOT NULL UNIQUE,
    locale     TEXT NOT NULL DEFAULT 'pt-BR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
