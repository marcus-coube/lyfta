DROP TRIGGER IF EXISTS trg_workout_set_logs_append_only ON workout_set_logs;
DROP TRIGGER IF EXISTS trg_prescribed_sets_guard ON prescribed_sets;
DROP TRIGGER IF EXISTS trg_block_exercises_guard ON block_exercises;
DROP TRIGGER IF EXISTS trg_workout_blocks_guard ON workout_blocks;
DROP TRIGGER IF EXISTS trg_workout_days_guard ON workout_days;
DROP TRIGGER IF EXISTS trg_workout_plan_versions_guard ON workout_plan_versions;

DROP FUNCTION IF EXISTS workout_set_logs_append_only();
DROP FUNCTION IF EXISTS prescribed_sets_guard();
DROP FUNCTION IF EXISTS block_exercises_guard();
DROP FUNCTION IF EXISTS workout_blocks_guard();
DROP FUNCTION IF EXISTS workout_days_guard();
DROP FUNCTION IF EXISTS workout_plan_versions_guard();
DROP FUNCTION IF EXISTS workout_version_is_published(UUID);
