DROP FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ, UUID[]);

CREATE FUNCTION find_pending_students(p_since TIMESTAMPTZ, p_until TIMESTAMPTZ)
RETURNS TABLE (tenant_id UUID, student_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT s.tenant_id, s.student_id
    FROM student_plan_state s
    WHERE NOT EXISTS (
        SELECT 1 FROM workout_sessions ws
        WHERE ws.tenant_id = s.tenant_id
          AND ws.student_id = s.student_id
          AND ws.received_at >= p_since
          AND ws.received_at < p_until
    );
$$;

REVOKE ALL ON FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ) TO lyfta_app;
