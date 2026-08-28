-- workout_plans: template do aluno, mutável e versionado (ADR-004 §1).
-- student_id/coach_id são users.id do identity — UUID sem FK (ADR-013 §2).
CREATE TABLE workout_plans (
    id         UUID PRIMARY KEY,
    tenant_id  UUID NOT NULL,
    student_id UUID NOT NULL,
    coach_id   UUID NOT NULL,
    title      TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft', 'published', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_workout_plans_student ON workout_plans (tenant_id, student_id, created_at DESC);
CREATE INDEX idx_workout_plans_coach ON workout_plans (tenant_id, coach_id, created_at DESC);

ALTER TABLE workout_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_plans FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_plans
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
