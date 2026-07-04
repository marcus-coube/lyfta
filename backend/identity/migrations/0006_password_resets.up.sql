-- password_resets: recuperação de senha (P0.4). tenant_id denormalizado de
-- users (ver nota em user_roles).
CREATE TABLE password_resets (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id  UUID NOT NULL REFERENCES tenants(id),
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_password_resets_tenant_id ON password_resets (tenant_id, user_id);
CREATE UNIQUE INDEX idx_password_resets_token_hash ON password_resets (token_hash);

ALTER TABLE password_resets ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_resets FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON password_resets
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
