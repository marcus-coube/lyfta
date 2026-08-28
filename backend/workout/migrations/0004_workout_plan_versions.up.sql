-- workout_plan_versions: editar um plano publicado gera versão nova; versões
-- publicadas são imutáveis (ADR-004 §1) — garantido por trigger na 0012.
-- published_at NULL = rascunho ainda editável.
CREATE TABLE workout_plan_versions (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    plan_id      UUID NOT NULL REFERENCES workout_plans(id) ON DELETE CASCADE,
    version_no   INTEGER NOT NULL CHECK (version_no > 0),
    published_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plan_id, version_no)
);

CREATE INDEX idx_workout_plan_versions_plan ON workout_plan_versions (tenant_id, plan_id, version_no DESC);

ALTER TABLE workout_plan_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_plan_versions FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_plan_versions
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
