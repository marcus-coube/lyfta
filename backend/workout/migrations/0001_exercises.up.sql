-- exercises: biblioteca em dois níveis (ADR-010 §3).
--   tenant_id NULL  = exercício global da Lyfta, somente leitura para tenants
--   tenant_id setado = exercício próprio do tenant (coach criou ou clonou)
-- created_by referencia users.id do serviço identity: banco por serviço
-- (ADR-013 §2), logo é UUID sem FK — nenhuma FK cruza bancos.
CREATE TABLE exercises (
    id             UUID PRIMARY KEY,
    tenant_id      UUID,
    name           TEXT NOT NULL,
    primary_muscle TEXT NOT NULL,
    equipment      TEXT NOT NULL,
    level          TEXT NOT NULL DEFAULT 'beginner'
                       CHECK (level IN ('beginner', 'intermediate', 'advanced')),
    media_url      TEXT,
    media_type     TEXT CHECK (media_type IN ('gif', 'video')),
    created_by     UUID,
    status         TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'archived')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- mídia é opcional, mas URL sem tipo (ou o contrário) não é estado válido.
    CONSTRAINT exercises_media_complete CHECK (
        (media_url IS NULL AND media_type IS NULL)
        OR (media_url IS NOT NULL AND media_type IS NOT NULL)
    )
);

CREATE INDEX idx_exercises_tenant_name ON exercises (tenant_id, name);
CREATE INDEX idx_exercises_muscle ON exercises (tenant_id, primary_muscle);

ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises FORCE ROW LEVEL SECURITY;

-- Policy dupla (P1.1): qualquer tenant lê os globais; escrita só nos próprios.
-- Os globais são semeados por processo administrativo (superusuário/seed),
-- nunca pela API — por isso nenhuma policy de escrita cobre tenant_id NULL.
CREATE POLICY tenant_read ON exercises FOR SELECT
    USING (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_insert ON exercises FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_update ON exercises FOR UPDATE
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_delete ON exercises FOR DELETE
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
