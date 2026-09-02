-- progress_photos: fotos antes/depois (ADR-012 §2). media_key é o caminho no
-- bucket S3-compatible (presign entra na P2.3); a foto só existe com mídia,
-- então media_key é obrigatório — diferente de exercises.media_url, que é
-- opcional porque um exercício pode não ter mídia nenhuma.
CREATE TABLE progress_photos (
    id          UUID PRIMARY KEY,
    tenant_id   UUID NOT NULL,
    student_id  UUID NOT NULL,
    taken_at    DATE NOT NULL,
    pose        TEXT NOT NULL CHECK (pose IN ('front', 'side', 'back')),
    media_key   TEXT NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_progress_photos_student ON progress_photos (tenant_id, student_id, taken_at DESC);

ALTER TABLE progress_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress_photos FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON progress_photos
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
