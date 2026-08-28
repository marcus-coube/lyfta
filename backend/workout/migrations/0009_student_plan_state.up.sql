-- student_plan_state: rotação A→B→C por aluno (ADR-004 §3) — plano ativo,
-- próximo dia e última execução. Um estado por aluno dentro do tenant; o
-- aluno/coach pode sobrescrever next_day_id manualmente.
CREATE TABLE student_plan_state (
    tenant_id         UUID NOT NULL,
    student_id        UUID NOT NULL,
    plan_id           UUID NOT NULL REFERENCES workout_plans(id) ON DELETE CASCADE,
    active_version_id UUID NOT NULL REFERENCES workout_plan_versions(id),
    next_day_id       UUID REFERENCES workout_days(id),
    last_session_at   TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, student_id)
);

ALTER TABLE student_plan_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_plan_state FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON student_plan_state
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
