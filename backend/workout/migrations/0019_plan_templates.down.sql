DROP INDEX IF EXISTS idx_workout_plans_source_template;
DROP INDEX IF EXISTS idx_workout_plans_kind_updated;
-- Modelos não cabem no schema anterior (student_id NOT NULL) e suas versões
-- publicadas são imutáveis (trigger 0012): apagá-los é decisão humana.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM workout_plans WHERE kind = 'template') THEN
        RAISE EXCEPTION 'existem modelos de treino; remova-os manualmente antes de reverter a 0019';
    END IF;
END $$;
ALTER TABLE workout_plans
    DROP CONSTRAINT IF EXISTS workout_plans_kind_student,
    ALTER COLUMN student_id SET NOT NULL,
    DROP COLUMN IF EXISTS edited_after_source,
    DROP COLUMN IF EXISTS source_version_no,
    DROP COLUMN IF EXISTS source_template_id,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS kind;
