-- Imutabilidade no banco, não só na aplicação: são as duas garantias que os
-- ADRs 003/004 tratam como invariantes do produto, e um bug de handler não
-- pode ser capaz de reescrever o passado do aluno.
--   1. versão publicada não muda mais (ADR-004 §1) — nem ela, nem sua árvore
--   2. log de série é append-only (ADR-003 §2) — correção vira novo log
--      com `revises`, nunca UPDATE/DELETE

-- 1. Versões publicadas -------------------------------------------------

CREATE FUNCTION workout_version_is_published(p_version_id UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM workout_plan_versions v
        WHERE v.id = p_version_id AND v.published_at IS NOT NULL
    );
$$;

-- Publicar (published_at NULL -> timestamp) é o último UPDATE permitido.
CREATE FUNCTION workout_plan_versions_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.published_at IS NOT NULL THEN
        RAISE EXCEPTION 'workout_plan_versions: versão publicada é imutável (ADR-004 §1)'
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_workout_plan_versions_guard
    BEFORE UPDATE OR DELETE ON workout_plan_versions
    FOR EACH ROW EXECUTE FUNCTION workout_plan_versions_guard();

CREATE FUNCTION workout_days_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_version_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_version_id := OLD.plan_version_id;
    ELSE
        v_version_id := NEW.plan_version_id;
    END IF;

    IF workout_version_is_published(v_version_id) THEN
        RAISE EXCEPTION 'workout_days: a versão do plano já foi publicada (ADR-004 §1)'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_workout_days_guard
    BEFORE INSERT OR UPDATE OR DELETE ON workout_days
    FOR EACH ROW EXECUTE FUNCTION workout_days_guard();

CREATE FUNCTION workout_blocks_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_version_id UUID;
BEGIN
    SELECT d.plan_version_id INTO v_version_id
    FROM workout_days d
    WHERE d.id = CASE WHEN TG_OP = 'DELETE' THEN OLD.day_id ELSE NEW.day_id END;

    IF workout_version_is_published(v_version_id) THEN
        RAISE EXCEPTION 'workout_blocks: a versão do plano já foi publicada (ADR-004 §1)'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_workout_blocks_guard
    BEFORE INSERT OR UPDATE OR DELETE ON workout_blocks
    FOR EACH ROW EXECUTE FUNCTION workout_blocks_guard();

CREATE FUNCTION block_exercises_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_version_id UUID;
BEGIN
    SELECT d.plan_version_id INTO v_version_id
    FROM workout_blocks b
    JOIN workout_days d ON d.id = b.day_id
    WHERE b.id = CASE WHEN TG_OP = 'DELETE' THEN OLD.block_id ELSE NEW.block_id END;

    IF workout_version_is_published(v_version_id) THEN
        RAISE EXCEPTION 'block_exercises: a versão do plano já foi publicada (ADR-004 §1)'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_block_exercises_guard
    BEFORE INSERT OR UPDATE OR DELETE ON block_exercises
    FOR EACH ROW EXECUTE FUNCTION block_exercises_guard();

CREATE FUNCTION prescribed_sets_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_version_id UUID;
BEGIN
    SELECT d.plan_version_id INTO v_version_id
    FROM block_exercises be
    JOIN workout_blocks b ON b.id = be.block_id
    JOIN workout_days d ON d.id = b.day_id
    WHERE be.id = CASE WHEN TG_OP = 'DELETE' THEN OLD.block_exercise_id ELSE NEW.block_exercise_id END;

    IF workout_version_is_published(v_version_id) THEN
        RAISE EXCEPTION 'prescribed_sets: a versão do plano já foi publicada (ADR-004 §1)'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prescribed_sets_guard
    BEFORE INSERT OR UPDATE OR DELETE ON prescribed_sets
    FOR EACH ROW EXECUTE FUNCTION prescribed_sets_guard();

-- 2. Logs append-only ---------------------------------------------------

CREATE FUNCTION workout_set_logs_append_only() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'workout_set_logs: append-only — corrija criando um log com revises (ADR-003 §5)'
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER trg_workout_set_logs_append_only
    BEFORE UPDATE OR DELETE ON workout_set_logs
    FOR EACH ROW EXECUTE FUNCTION workout_set_logs_append_only();
