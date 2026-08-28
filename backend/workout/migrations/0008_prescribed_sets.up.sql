-- prescribed_sets: prescrição ESTRUTURADA por set (ADR-012 §4) — é o
-- pré-requisito do gráfico de carga do MVP 1.0; nada de texto livre aqui.
--   reps_min/reps_max  -> faixa de repetições (min = max quando é número fixo)
--   target_load_kg     -> carga alvo absoluta, quando o coach prescreve em kg
--   target_unit/value  -> alvo alternativo: %1RM, RPE ou RIR
CREATE TABLE prescribed_sets (
    id                 UUID PRIMARY KEY,
    tenant_id          UUID NOT NULL,
    block_exercise_id  UUID NOT NULL REFERENCES block_exercises(id) ON DELETE CASCADE,
    set_no             INTEGER NOT NULL CHECK (set_no > 0),
    reps_min           INTEGER CHECK (reps_min >= 0),
    reps_max           INTEGER CHECK (reps_max >= 0),
    target_load_kg     NUMERIC(6, 2) CHECK (target_load_kg >= 0),
    target_unit        TEXT CHECK (target_unit IN ('kg', 'percent_1rm', 'rpe', 'rir')),
    target_value       NUMERIC(6, 2) CHECK (target_value >= 0),
    rest_seconds       INTEGER CHECK (rest_seconds >= 0),
    tempo              TEXT,
    UNIQUE (block_exercise_id, set_no),
    CONSTRAINT prescribed_sets_reps_range CHECK (
        reps_min IS NULL OR reps_max IS NULL OR reps_max >= reps_min
    ),
    -- alvo relativo (%1RM/RPE/RIR) sem valor não prescreve nada.
    CONSTRAINT prescribed_sets_target_complete CHECK (
        target_unit IS NULL OR target_unit = 'kg' OR target_value IS NOT NULL
    )
);

CREATE INDEX idx_prescribed_sets_block_exercise ON prescribed_sets (tenant_id, block_exercise_id, set_no);

ALTER TABLE prescribed_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescribed_sets FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON prescribed_sets
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
