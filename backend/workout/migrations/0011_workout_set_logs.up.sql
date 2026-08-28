-- workout_set_logs: fato imutável de uma série executada (ADR-003 §2).
-- Append-only garantido por trigger na 0012 — corrigir um registro errado não
-- edita o fato: cria outro log com `revises` apontando para o client_id do
-- log revisado (ADR-003 §5).
-- exercise_id é o eixo estável de progresso entre versões do plano (ADR-004).
CREATE TABLE workout_set_logs (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    session_id   UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id  UUID NOT NULL REFERENCES exercises(id),
    set_no       INTEGER NOT NULL CHECK (set_no > 0),
    reps_done    INTEGER CHECK (reps_done >= 0),
    load_kg      NUMERIC(6, 2) CHECK (load_kg >= 0),
    rpe          NUMERIC(3, 1) CHECK (rpe >= 0 AND rpe <= 10),
    performed_at TIMESTAMPTZ NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    client_id    UUID NOT NULL,
    revises      UUID,
    UNIQUE (tenant_id, client_id)
);

CREATE INDEX idx_workout_set_logs_session ON workout_set_logs (tenant_id, session_id, set_no);
-- "carga anterior": último log do aluno para o mesmo exercise_id (ADR-004).
CREATE INDEX idx_workout_set_logs_exercise ON workout_set_logs (tenant_id, exercise_id, performed_at DESC);

ALTER TABLE workout_set_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_set_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_set_logs
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
