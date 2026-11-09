-- P5.1: o job de treino pendente do comms roda por fuso de tenant (ADR-007
-- §3), então a pergunta deixa de ser "de todos os tenants" e passa a ser
-- "destes tenants". A função continua SECURITY DEFINER (quem chama é M2M, sem
-- app.tenant_id), mas agora recebe a lista explícita de tenants e nunca
-- devolve aluno de tenant que não foi pedido.
DROP FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ);

CREATE FUNCTION find_pending_students(p_since TIMESTAMPTZ, p_until TIMESTAMPTZ, p_tenant_ids UUID[])
RETURNS TABLE (tenant_id UUID, student_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT s.tenant_id, s.student_id
    FROM student_plan_state s
    WHERE s.tenant_id = ANY (p_tenant_ids)
      AND NOT EXISTS (
        SELECT 1 FROM workout_sessions ws
        WHERE ws.tenant_id = s.tenant_id
          AND ws.student_id = s.student_id
          AND ws.received_at >= p_since
          AND ws.received_at < p_until
    );
$$;

REVOKE ALL ON FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_pending_students(TIMESTAMPTZ, TIMESTAMPTZ, UUID[]) TO lyfta_app;
