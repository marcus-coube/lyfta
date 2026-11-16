-- session_media: mídia (vídeo/foto) que o aluno anexa durante o treino para o
-- professor avaliar o movimento (ADR-020, P12.1). Chaveada por
-- session_client_id, o mesmo UUID do check-in e da sessão no workout, sem FK
-- entre bancos (ADR-013 §2); exercise_id/exercise_name são cópias.
--
-- Primeiro dado do sistema com prazo de vida: delete_after nasce em
-- created_at + 30 dias e o ack do professor o antecipa para acked_at + 7 dias
-- (LEAST, nunca adia). O job apaga o objeto e marca deleted_at; a linha fica
-- sem a chave para o histórico "mídia expirada".
CREATE TABLE session_media (
    id                UUID PRIMARY KEY,
    tenant_id         UUID NOT NULL,
    student_id        UUID NOT NULL,
    session_client_id UUID NOT NULL,
    exercise_id       UUID,
    exercise_name     TEXT CHECK (char_length(exercise_name) <= 200),
    media_key         TEXT,
    content_type      TEXT NOT NULL,
    size_bytes        BIGINT NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 20971520),
    note              TEXT CHECK (char_length(note) <= 280),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    acked_by          UUID,
    acked_at          TIMESTAMPTZ,
    delete_after      TIMESTAMPTZ NOT NULL,
    deleted_at        TIMESTAMPTZ,
    UNIQUE (tenant_id, media_key)
);

-- Ficha do aluno em ordem cronológica e mídia por sessão.
CREATE INDEX idx_session_media_student ON session_media (tenant_id, student_id, created_at DESC);
-- Job de expiração: só o que ainda tem objeto a apagar.
CREATE INDEX idx_session_media_due ON session_media (tenant_id, delete_after) WHERE deleted_at IS NULL;
-- "Para avaliar" do coach: sem ciência e ainda não expirada.
CREATE INDEX idx_session_media_pending ON session_media (tenant_id, created_at DESC)
    WHERE acked_at IS NULL AND deleted_at IS NULL;

ALTER TABLE session_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_media FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON session_media
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON session_media TO lyfta_app;
