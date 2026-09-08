-- messages: histórico append-only de uma conversa (ADR-012 §2 — texto ou
-- imagem). read_at nulo = não lida; marcado em lote por POST .../read (P3.2).
-- media_key segue o padrão de tenants/{t}/chat/{conv}/{uuid} (presign padrão
-- dos demais serviços), preenchido só quando type = 'image'.
CREATE TABLE messages (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL,
    type            TEXT NOT NULL CHECK (type IN ('text', 'image')),
    body            TEXT,
    media_key       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at         TIMESTAMPTZ,
    CONSTRAINT messages_content_matches_type CHECK (
        (type = 'text' AND body IS NOT NULL AND media_key IS NULL)
        OR (type = 'image' AND media_key IS NOT NULL)
    )
);

-- Histórico por conversa em cursor desc (P3.2 — GET .../messages).
CREATE INDEX idx_messages_conversation ON messages (tenant_id, conversation_id, created_at DESC);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON messages
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
