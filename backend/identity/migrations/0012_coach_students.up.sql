-- coach_students: vínculo professor↔aluno (ADR-016, P4.7). 1 coach principal
-- por aluno (PK com o tenant), coach_id NOT NULL: nunca existe aluno sem
-- professor. Histórico de vínculos fica fora (só quem atribuiu e quando).
CREATE TABLE coach_students (
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    student_id  UUID NOT NULL REFERENCES users(id),
    coach_id    UUID NOT NULL REFERENCES users(id),
    assigned_by UUID REFERENCES users(id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, student_id)
);

CREATE INDEX idx_coach_students_coach ON coach_students (tenant_id, coach_id);

ALTER TABLE coach_students ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_students FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON coach_students
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON coach_students TO lyfta_app;

-- Backfill (roda como superusuário, então ignora RLS): todo aluno existente
-- ganha o coach que o convidou, se ainda for um usuário ativo coach|owner;
-- senão o owner ativo mais antigo do tenant. Tenant sem owner ativo deixa o
-- aluno sem vínculo (não existe na prática: o signup cria o owner).
INSERT INTO coach_students (tenant_id, student_id, coach_id)
SELECT tenant_id, student_id, coach_id
FROM (
    SELECT u.tenant_id, u.id AS student_id,
           COALESCE(
               (SELECT i.invited_by
                FROM invitations i
                JOIN users c ON c.id = i.invited_by AND c.status = 'active'
                WHERE i.tenant_id = u.tenant_id AND i.email = u.email AND i.role = 'student'
                  AND EXISTS (SELECT 1 FROM user_roles r
                              WHERE r.user_id = c.id AND r.role IN ('coach', 'owner'))
                ORDER BY i.created_at LIMIT 1),
               (SELECT o.id
                FROM users o
                JOIN user_roles r ON r.user_id = o.id AND r.role = 'owner'
                WHERE o.tenant_id = u.tenant_id AND o.status = 'active'
                ORDER BY o.created_at LIMIT 1)
           ) AS coach_id
    FROM users u
    JOIN user_roles sr ON sr.user_id = u.id AND sr.role = 'student'
    WHERE u.status IN ('invited', 'active', 'disabled')
) candidates
WHERE coach_id IS NOT NULL
ON CONFLICT DO NOTHING;
