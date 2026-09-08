-- Role de aplicação sem BYPASSRLS (ADR-001 §2), espelhando a 0007 do
-- identity, a 0013 do workout e a 0004 do assessment: o serviço conecta com
-- ela para que as policies realmente se apliquem — um superusuário ignora RLS
-- mesmo com FORCE ROW LEVEL SECURITY.
-- Roda por último para conceder privilégios nas tabelas já criadas.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'lyfta_app') THEN
        CREATE ROLE lyfta_app LOGIN PASSWORD 'lyfta_app_dev' NOBYPASSRLS;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE lyfta_comms TO lyfta_app;
GRANT USAGE ON SCHEMA public TO lyfta_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO lyfta_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO lyfta_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lyfta_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO lyfta_app;
