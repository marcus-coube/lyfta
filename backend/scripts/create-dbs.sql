-- Cria os bancos dos microserviços (ADR-013). Idempotente.
-- Uso: psql -U postgres -f backend/scripts/create-dbs.sql
SELECT 'CREATE DATABASE duo_identity'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'duo_identity')\gexec
SELECT 'CREATE DATABASE duo_workout'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'duo_workout')\gexec
SELECT 'CREATE DATABASE duo_assessment'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'duo_assessment')\gexec
SELECT 'CREATE DATABASE duo_comms'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'duo_comms')\gexec
SELECT 'CREATE DATABASE duo_billing'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'duo_billing')\gexec
