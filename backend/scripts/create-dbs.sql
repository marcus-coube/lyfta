-- Cria os bancos dos microserviços (ADR-013). Idempotente.
-- Uso: psql -U postgres -f backend/scripts/create-dbs.sql
SELECT 'CREATE DATABASE lyfta_identity'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lyfta_identity')\gexec
SELECT 'CREATE DATABASE lyfta_workout'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lyfta_workout')\gexec
SELECT 'CREATE DATABASE lyfta_assessment'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lyfta_assessment')\gexec
SELECT 'CREATE DATABASE lyfta_comms'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lyfta_comms')\gexec
