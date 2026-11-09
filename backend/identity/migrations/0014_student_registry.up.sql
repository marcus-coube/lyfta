-- Cadastro e ciclo de vida do aluno (P5.2). `phone` e `birth_date` são
-- opcionais. `inactive` é o aluno desativado pelo professor/owner: não loga,
-- some da lista padrão e mantém todos os dados; `disabled` segue para bloqueio
-- administrativo.
ALTER TABLE users
    ADD COLUMN phone TEXT,
    ADD COLUMN birth_date DATE;

ALTER TABLE users DROP CONSTRAINT users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('invited', 'active', 'inactive', 'disabled', 'deleting', 'deleted'));

-- Histórico das transições de status: aceite do convite (invited → active,
-- autor = o próprio usuário) e inativar/reativar.
-- Append-only: a aplicação só insere. O DELETE existe só para a exclusão de
-- conta (ADR-008 §2), porque `reason` é texto livre e pode citar a pessoa.
CREATE TABLE user_status_events (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    user_id     UUID NOT NULL REFERENCES users(id),
    from_status TEXT NOT NULL,
    to_status   TEXT NOT NULL,
    changed_by  UUID NOT NULL REFERENCES users(id),
    reason      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_status_events_user ON user_status_events (tenant_id, user_id, created_at DESC);

ALTER TABLE user_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_status_events FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON user_status_events
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

GRANT SELECT, INSERT, DELETE ON user_status_events TO lyfta_app;
