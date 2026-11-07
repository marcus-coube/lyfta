-- consents: registro append-only de consentimento por finalidade (ADR-008 §1,
-- P4.5). Revogar grava revoked_at — a linha nunca é apagada, é a prova do que
-- o titular concedeu e quando. Conceder de novo depois de revogar (ou numa
-- versão nova dos termos) cria outra linha. No máximo uma linha vigente
-- (revoked_at NULL) por usuário e finalidade.
CREATE TABLE consents (
    id            UUID PRIMARY KEY,
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    user_id       UUID NOT NULL REFERENCES users(id),
    purpose       TEXT NOT NULL CHECK (purpose IN ('terms', 'health_data', 'progress_photos')),
    terms_version TEXT NOT NULL,
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at    TIMESTAMPTZ
);

CREATE INDEX idx_consents_tenant_user ON consents (tenant_id, user_id, purpose);
CREATE UNIQUE INDEX idx_consents_active ON consents (tenant_id, user_id, purpose) WHERE revoked_at IS NULL;

ALTER TABLE consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE consents FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON consents
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON consents TO lyfta_app;
