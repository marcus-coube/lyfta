DROP TABLE user_status_events;

UPDATE users SET status = 'disabled' WHERE status = 'inactive';
ALTER TABLE users DROP CONSTRAINT users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('invited', 'active', 'disabled', 'deleting', 'deleted'));

ALTER TABLE users
    DROP COLUMN birth_date,
    DROP COLUMN phone;
