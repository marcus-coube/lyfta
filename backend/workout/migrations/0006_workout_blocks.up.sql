-- workout_blocks: agrupamento que representa superset/circuito/drop set
-- (ADR-004 §1). Exercício "normal" é um bloco straight de um exercício só.
CREATE TABLE workout_blocks (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    day_id       UUID NOT NULL REFERENCES workout_days(id) ON DELETE CASCADE,
    position     INTEGER NOT NULL CHECK (position >= 0),
    block_type   TEXT NOT NULL DEFAULT 'straight'
                     CHECK (block_type IN ('straight', 'superset', 'dropset', 'rest_pause', 'circuit')),
    rest_seconds INTEGER NOT NULL DEFAULT 0 CHECK (rest_seconds >= 0),
    UNIQUE (day_id, position)
);

CREATE INDEX idx_workout_blocks_day ON workout_blocks (tenant_id, day_id, position);

ALTER TABLE workout_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_blocks FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_blocks
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
