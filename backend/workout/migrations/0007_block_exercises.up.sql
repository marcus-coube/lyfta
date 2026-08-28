-- block_exercises: qual exercício ocupa cada posição do bloco.
-- FK para exercises é intra-banco (mesmo serviço), diferente das referências a
-- users/tenants do identity, que são UUID solto (ADR-013 §2).
CREATE TABLE block_exercises (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL,
    block_id    UUID NOT NULL REFERENCES workout_blocks(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    position    INTEGER NOT NULL CHECK (position >= 0),
    notes       TEXT NOT NULL DEFAULT '',
    UNIQUE (block_id, position)
);

CREATE INDEX idx_block_exercises_block ON block_exercises (tenant_id, block_id, position);
CREATE INDEX idx_block_exercises_exercise ON block_exercises (tenant_id, exercise_id);

ALTER TABLE block_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE block_exercises FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON block_exercises
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
