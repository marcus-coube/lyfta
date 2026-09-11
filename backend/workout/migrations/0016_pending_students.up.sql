-- GET /internal/v1/pending-students (P3.4, M2M do comms — ADR-013 §4/§5)
-- precisa cruzar aluno com plano ativo × sessão registrada num intervalo,
-- ATRAVÉS DE TODOS OS TENANTS: é uma consulta de job interno (o comms varre
-- todo mundo uma vez por dia), não uma requisição de usuário com
-- app.tenant_id setado. Mesma situação e mesma solução do
-- find_tenants_by_email do identity (0008_email_lookup): função SQL
-- SECURITY DEFINER de superfície mínima — ignora RLS só para esta pergunta
-- específica (quem tem plano ativo e não treinou no intervalo informado) e
-- nunca expõe conteúdo de treino, só os dois ids que o comms precisa (quem
-- notificar e sob qual tenant).
--
-- "Plano ativo" segue o mesmo critério já usado pelo resto do serviço
-- (GetState, MyPlan): ter uma linha em student_plan_state — ela só existe
-- depois de um Publish e é sempre reescrita para apontar pro plano
-- atualmente publicado do aluno (repo/plans.go), então não precisa reconferir
-- workout_plans.status aqui.
--
-- "Sem sessão no intervalo" usa `received_at` (carimbo do servidor,
-- ADR-003 §2), não `started_at` (relógio do device, não confiável) — é o
-- mesmo campo que a P1.5 já trata como fonte de verdade para "quando o
-- servidor soube que o aluno treinou".
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
