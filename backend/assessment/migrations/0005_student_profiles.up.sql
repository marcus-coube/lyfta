-- Anamnese (P5.3): objetivo, experiência e restrições do aluno. Dado de saúde
-- (ADR-008 §1): vive no assessment e é apagado fisicamente na exclusão de
-- conta. student_id/updated_by/created_by referenciam users.id do identity:
-- banco por serviço (ADR-013 §2), logo UUID sem FK.

-- Uma linha por aluno; nasce no primeiro PUT. Códigos estáveis nos CHECKs
-- (ADR-011: o rótulo traduzido é do cliente). coach_notes é só do coach: a
-- porta /me nunca a seleciona.
CREATE TABLE student_profiles (
    tenant_id           UUID NOT NULL,
    student_id          UUID NOT NULL,
    goal                TEXT CHECK (goal IN ('hypertrophy', 'weight_loss', 'strength', 'conditioning', 'health', 'rehab', 'other')),
    goal_notes          TEXT,
    training_experience TEXT CHECK (training_experience IN ('beginner', 'intermediate', 'advanced')),
    weekly_target       SMALLINT CHECK (weekly_target BETWEEN 1 AND 7),
    medical_notes       TEXT,
    coach_notes         TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          UUID NOT NULL,
    PRIMARY KEY (tenant_id, student_id)
);

ALTER TABLE student_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_profiles FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON student_profiles
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- Lesões e restrições. `resolved_at` preenchido = saiu da lista de ativas.
CREATE TABLE student_injuries (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL,
    student_id  UUID NOT NULL,
    body_region TEXT NOT NULL CHECK (body_region IN ('neck', 'shoulder', 'elbow', 'wrist_hand', 'upper_back', 'lower_back', 'chest', 'hip', 'knee', 'ankle_foot', 'other')),
    description TEXT NOT NULL,
    since       DATE,
    resolved_at DATE,
    created_by  UUID NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_student_injuries_student ON student_injuries (tenant_id, student_id, created_at DESC);

ALTER TABLE student_injuries ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_injuries FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON student_injuries
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
