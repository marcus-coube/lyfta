-- A role é compartilhada com os outros bancos (identity, workout, assessment):
-- a queda reverte só os privilégios deste banco, nunca dropa a role.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM duo_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM duo_app;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM duo_app;
REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM duo_app;
REVOKE USAGE ON SCHEMA public FROM duo_app;
REVOKE CONNECT ON DATABASE duo_comms FROM duo_app;
