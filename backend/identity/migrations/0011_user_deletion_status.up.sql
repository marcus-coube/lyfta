-- Exclusão de conta (ADR-008 §2, P4.5): `deleting` = login bloqueado enquanto
-- os serviços apagam os dados do usuário; `deleted` = usuário anonimizado.
ALTER TABLE users DROP CONSTRAINT users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('invited', 'active', 'disabled', 'deleting', 'deleted'));
