DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM workout_blocks WHERE block_type = 'cluster') THEN
        RAISE EXCEPTION 'existem blocos cluster; remova-os antes de reverter a 0021';
    END IF;
END $$;

ALTER TABLE prescribed_sets DROP COLUMN label;

ALTER TABLE workout_blocks DROP CONSTRAINT workout_blocks_block_type_check;
ALTER TABLE workout_blocks ADD CONSTRAINT workout_blocks_block_type_check
    CHECK (block_type IN ('straight', 'superset', 'dropset', 'rest_pause', 'circuit'));
