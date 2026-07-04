-- Role de aplicação sem BYPASSRLS (ADR-001 §2, plano P0.2): o serviço
-- identity deve conectar com esta role (DATABASE_URL) para que as policies
-- de RLS realmente se apliquem — um superusuário (ex.: postgres) ou o dono
-- das tabelas sempre ignora RLS, mesmo com FORCE ROW LEVEL SECURITY.
-- Migration roda por último (depois de todas as tabelas existirem) para
-- poder conceder privilégios nas tabelas já criadas, além de default
-- privileges para tabelas futuras.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'lyfta_app') THEN
        CREATE ROLE lyfta_app LOGIN PASSWORD 'lyfta_app_dev' NOBYPASSRLS;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE lyfta_identity TO lyfta_app;
GRANT USAGE ON SCHEMA public TO lyfta_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO lyfta_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lyfta_app;
