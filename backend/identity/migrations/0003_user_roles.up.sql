-- user_roles: um usuário pode acumular papéis (ex.: coach que também treina).
-- tenant_id denormalizado de users para permitir RLS direta na tabela
-- (ADR-001 §1/§3: toda tabela de domínio tem tenant_id + índice iniciando
-- nele), sem depender de subquery a users a cada policy.
CREATE TABLE user_roles (
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    role      TEXT NOT NULL CHECK (role IN ('owner', 'coach', 'student')),
    PRIMARY KEY (user_id, role)
);

CREATE INDEX idx_user_roles_tenant_id ON user_roles (tenant_id, user_id);

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON user_roles
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
