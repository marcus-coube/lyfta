-- workout_sessions: execução (ADR-004 §2). O snapshot desnormalizado é
-- congelado no início da sessão — o histórico do aluno nunca depende do
-- template vivo. client_id é o UUID gerado no device (ADR-003 §2): chave de
-- idempotência do push offline, único por tenant.
CREATE TABLE workout_sessions (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    student_id      UUID NOT NULL,
    plan_version_id UUID NOT NULL REFERENCES workout_plan_versions(id),
    day_id          UUID NOT NULL REFERENCES workout_days(id),
    snapshot        JSONB NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    client_id       UUID NOT NULL,
    -- ADR-003: o relógio do device não é confiável; o servidor carimba quando
    -- recebeu, separado do que o device diz ter acontecido.
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, client_id)
);

CREATE INDEX idx_workout_sessions_student ON workout_sessions (tenant_id, student_id, started_at DESC);

ALTER TABLE workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_sessions FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_sessions
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
