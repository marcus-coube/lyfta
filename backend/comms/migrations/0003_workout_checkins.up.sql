-- workout_checkins: avaliação estruturada do aluno ao concluir o treino
-- (ADR-012 §2). session_client_id é o client_id da sessão no serviço workout
-- (ADR-003 §2) — o mesmo UUID gerado no device, sem FK entre bancos
-- (ADR-013 §2). Único por tenant+session_client_id: reenvio da mesma sessão
-- não duplica o check-in (P3.3, idempotência mesmo padrão do workout).
CREATE TABLE workout_checkins (
    id                UUID PRIMARY KEY,
    tenant_id         UUID NOT NULL,
    student_id        UUID NOT NULL,
    session_client_id UUID NOT NULL,
    rating            SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    difficulty        SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    pain              TEXT NOT NULL DEFAULT 'none' CHECK (pain IN ('none', 'mild', 'strong')),
    pain_notes        TEXT,
    comment           TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by       UUID,
    reviewed_at       TIMESTAMPTZ,
    UNIQUE (tenant_id, session_client_id)
);

-- Ficha do aluno em ordem cronológica (P3.3).
CREATE INDEX idx_workout_checkins_student ON workout_checkins (tenant_id, student_id, created_at DESC);
-- Listagem do coach com não revisados primeiro (P3.3 Aceite).
CREATE INDEX idx_workout_checkins_pending ON workout_checkins (tenant_id, reviewed_at NULLS FIRST, created_at DESC);

ALTER TABLE workout_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_checkins FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON workout_checkins
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
