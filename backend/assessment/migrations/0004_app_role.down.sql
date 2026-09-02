-- A role é compartilhada com os outros bancos (identity, workout etc.): a
-- queda reverte só os privilégios deste banco, nunca dropa a role.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM lyfta_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM lyfta_app;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM lyfta_app;
REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM lyfta_app;
REVOKE USAGE ON SCHEMA public FROM lyfta_app;
REVOKE CONNECT ON DATABASE lyfta_assessment FROM lyfta_app;
