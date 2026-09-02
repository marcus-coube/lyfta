-- bioimpedance_records: entrada MANUAL (ADR-012 §2) — integração com balança
-- fica para 3.0+. Todos os campos de leitura são nullable: registra-se o que
-- o aparelho do coach mostrou.
CREATE TABLE bioimpedance_records (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    student_id      UUID NOT NULL,
    measured_at     DATE NOT NULL,
    body_fat_pct    NUMERIC(4, 1) CHECK (body_fat_pct >= 0 AND body_fat_pct <= 100),
    muscle_mass_kg  NUMERIC(5, 2) CHECK (muscle_mass_kg >= 0),
    visceral_fat    NUMERIC(4, 1) CHECK (visceral_fat >= 0),
    body_water_pct  NUMERIC(4, 1) CHECK (body_water_pct >= 0 AND body_water_pct <= 100),
    bone_mass_kg    NUMERIC(4, 2) CHECK (bone_mass_kg >= 0),
    bmr_kcal        INTEGER CHECK (bmr_kcal >= 0),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bioimpedance_records_student ON bioimpedance_records (tenant_id, student_id, measured_at DESC);

ALTER TABLE bioimpedance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE bioimpedance_records FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON bioimpedance_records
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
