-- notification_log: registro de cada push enviado (P3.4) — dedupe do job
-- diário "treino pendente" (1 envio por aluno/dia) e auditoria ("chegou
-- mesmo?"). payload guarda o corpo renderizado (locale do destinatário,
-- ADR-011: server renderiza push).
CREATE TABLE notification_log (
    id        UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,
    user_id   UUID NOT NULL,
    kind      TEXT NOT NULL,
    payload   JSONB NOT NULL DEFAULT '{}'::jsonb,
    sent_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dedupe diário (P3.4): "já mandei este `kind` pra este usuário hoje?" — sem
-- índice funcional (o cast timestamptz->date não é IMMUTABLE, depende do
-- timezone da sessão); a consulta de dedupe filtra por uma faixa
-- [início do dia, início do dia seguinte) do tenant sobre este índice.
CREATE INDEX idx_notification_log_dedupe ON notification_log (tenant_id, user_id, kind, sent_at DESC);

ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_log FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON notification_log
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
