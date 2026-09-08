-- conversations: 1 conversa por par aluno-coach (P3.1). Texto+imagem é o teto
-- do MVP (ADR-012 §2); mídia rica (áudio/vídeo/PDF) fica pro 3.0.
-- student_id/coach_id referenciam users.id do identity: banco por serviço
-- (ADR-013 §2), logo é UUID sem FK cruzando bancos.
CREATE TABLE conversations (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    student_id      UUID NOT NULL,
    coach_id        UUID NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ,
    UNIQUE (tenant_id, student_id, coach_id)
);

-- Aluno só tem 1 conversa (a sua); coach lista as suas ordenadas por
-- atividade recente (P3.2). Todo índice composto começa por tenant_id
-- (ADR-001 §3).
CREATE INDEX idx_conversations_student ON conversations (tenant_id, student_id);
CREATE INDEX idx_conversations_coach ON conversations (tenant_id, coach_id, last_message_at DESC);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON conversations
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
