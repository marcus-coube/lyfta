-- ADR-019: variações de execução do tenant ("Pausa no fundo"), vinculadas por
-- série. Conteúdo do tenant (sem autor dono); nunca se apaga — variação
-- usada por versão publicada só arquiva.
CREATE TABLE set_variations (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL,
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 1000),
    archived_at TIMESTAMPTZ,
    created_by  UUID NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_set_variations_tenant ON set_variations (tenant_id, archived_at, name);

-- Nome único por tenant entre as ativas; arquivar libera o nome.
CREATE UNIQUE INDEX uq_set_variations_active_name
    ON set_variations (tenant_id, lower(name)) WHERE archived_at IS NULL;

ALTER TABLE set_variations ENABLE ROW LEVEL SECURITY;
ALTER TABLE set_variations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON set_variations
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE prescribed_sets ADD COLUMN variation_id UUID REFERENCES set_variations(id);
CREATE INDEX idx_prescribed_sets_variation ON prescribed_sets (tenant_id, variation_id)
    WHERE variation_id IS NOT NULL;
