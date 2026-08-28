-- exercise_translations: conteúdo dinâmico traduzido (ADR-011 §2). O fallback
-- pt-PT → pt-BR → en é resolvido na query de leitura (P1.3), não no schema.
-- tenant_id espelha o do exercício (NULL para os globais) para a policy poder
-- decidir sem join com exercises.
CREATE TABLE exercise_translations (
    exercise_id  UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    tenant_id    UUID,
    locale       TEXT NOT NULL CHECK (locale IN ('pt-BR', 'pt-PT', 'en')),
    name         TEXT NOT NULL,
    instructions TEXT NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exercise_id, locale)
);

CREATE INDEX idx_exercise_translations_tenant ON exercise_translations (tenant_id, locale);

ALTER TABLE exercise_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercise_translations FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_read ON exercise_translations FOR SELECT
    USING (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_insert ON exercise_translations FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_update ON exercise_translations FOR UPDATE
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_delete ON exercise_translations FOR DELETE
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
