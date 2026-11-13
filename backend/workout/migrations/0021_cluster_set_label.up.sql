-- ADR-019: bloco `cluster` e rótulo opcional por série ("Aquecimento").
ALTER TABLE workout_blocks DROP CONSTRAINT workout_blocks_block_type_check;
ALTER TABLE workout_blocks ADD CONSTRAINT workout_blocks_block_type_check
    CHECK (block_type IN ('straight', 'superset', 'dropset', 'rest_pause', 'circuit', 'cluster'));

ALTER TABLE prescribed_sets ADD COLUMN label TEXT
    CONSTRAINT prescribed_sets_label_len CHECK (char_length(label) BETWEEN 1 AND 24);
