-- device_tokens: token de push por usuário+plataforma (P3.4). Único por
-- tenant+user+platform: reinstalar o app ou trocar de conta emite token novo,
-- e o registro (POST /v1/devices) faz upsert nessa chave.
CREATE TABLE device_tokens (
    id         UUID PRIMARY KEY,
    tenant_id  UUID NOT NULL,
    user_id    UUID NOT NULL,
    platform   TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    token      TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, user_id, platform)
);

CREATE INDEX idx_device_tokens_user ON device_tokens (tenant_id, user_id);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON device_tokens
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
