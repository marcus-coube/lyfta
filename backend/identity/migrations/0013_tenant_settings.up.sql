-- Configurações do tenant (P5.1): fuso (ADR-007 §3) e acesso do coach ao
-- financeiro (ADR-017 §3). `tenants` é global (sem RLS, ADR-001 §5).
-- O nome IANA é validado na aplicação (time.LoadLocation), não no banco.
ALTER TABLE tenants
    ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
    ADD COLUMN coach_billing_access TEXT NOT NULL DEFAULT 'status_only'
        CHECK (coach_billing_access IN ('status_only', 'own_students'));
