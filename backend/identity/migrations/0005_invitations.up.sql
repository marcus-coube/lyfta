-- invitations: convite do coach/owner para um e-mail entrar no tenant (P0.4).
CREATE TABLE invitations (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    email       TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('owner', 'coach', 'student')),
    token_hash  TEXT NOT NULL,
    invited_by  UUID NOT NULL REFERENCES users(id),
    expires_at  TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invitations_tenant_id ON invitations (tenant_id, email);
CREATE UNIQUE INDEX idx_invitations_token_hash ON invitations (token_hash);

ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON invitations
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
