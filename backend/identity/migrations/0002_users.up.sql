-- users: conta por tenant (ADR-002) — e-mail único por tenant, não global.
CREATE TABLE users (
    id            UUID PRIMARY KEY,
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    email         TEXT NOT NULL,
    password_hash TEXT NOT NULL DEFAULT '',
    name          TEXT NOT NULL,
    locale        TEXT NOT NULL DEFAULT 'pt-BR',
    status        TEXT NOT NULL DEFAULT 'invited'
                      CHECK (status IN ('invited', 'active', 'disabled')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, email)
);

CREATE INDEX idx_users_tenant_id ON users (tenant_id, email);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON users
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
