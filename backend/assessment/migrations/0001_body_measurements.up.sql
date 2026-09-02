-- body_measurements: medidas corporais digitadas manualmente (ADR-012 §2).
-- Registra-se só o que foi medido: todos os campos de circunferência/peso são
-- nullable, exceto os identificadores e a data. student_id referencia users.id
-- do serviço identity: banco por serviço (ADR-013 §2), logo é UUID sem FK.
CREATE TABLE body_measurements (
    id           UUID PRIMARY KEY,
    tenant_id    UUID NOT NULL,
    student_id   UUID NOT NULL,
    measured_at  DATE NOT NULL,
    weight_kg    NUMERIC(5, 2) CHECK (weight_kg > 0),
    height_cm    NUMERIC(5, 1) CHECK (height_cm > 0),
    neck_cm      NUMERIC(5, 1) CHECK (neck_cm >= 0),
    shoulder_cm  NUMERIC(5, 1) CHECK (shoulder_cm >= 0),
    chest_cm     NUMERIC(5, 1) CHECK (chest_cm >= 0),
    waist_cm     NUMERIC(5, 1) CHECK (waist_cm >= 0),
    abdomen_cm   NUMERIC(5, 1) CHECK (abdomen_cm >= 0),
    hip_cm       NUMERIC(5, 1) CHECK (hip_cm >= 0),
    arm_l_cm     NUMERIC(5, 1) CHECK (arm_l_cm >= 0),
    arm_r_cm     NUMERIC(5, 1) CHECK (arm_r_cm >= 0),
    thigh_l_cm   NUMERIC(5, 1) CHECK (thigh_l_cm >= 0),
    thigh_r_cm   NUMERIC(5, 1) CHECK (thigh_r_cm >= 0),
    calf_l_cm    NUMERIC(5, 1) CHECK (calf_l_cm >= 0),
    calf_r_cm    NUMERIC(5, 1) CHECK (calf_r_cm >= 0),
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Listagem por aluno, mais recente primeiro (P2.3 pagina por measured_at
-- desc); todo índice composto começa por tenant_id (ADR-001 §3).
CREATE INDEX idx_body_measurements_student ON body_measurements (tenant_id, student_id, measured_at DESC);

ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE body_measurements FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON body_measurements
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
