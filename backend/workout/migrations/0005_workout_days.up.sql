-- workout_days: os dias A/B/C… de uma versão do plano (ADR-004 §3, rotação).
CREATE TABLE workout_days (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    plan_version_id UUID NOT NULL REFERENCES workout_plan_versions(id) ON DELETE CASCADE,
    label           TEXT NOT NULL,
    position        INTEGER NOT NULL CHECK (position >= 0),
    title           TEXT NOT NULL DEFAULT '',
    UNIQUE (plan_version_id, position),
    UNIQUE (plan_version_id, label)
);

CREATE INDEX idx_workout_days_version ON workout_days (tenant_id, plan_version_id, position);

ALTER TABLE workout_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_days FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_days
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
