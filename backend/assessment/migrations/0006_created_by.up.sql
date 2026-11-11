-- P8.3: quem lançou o registro. Coach e aluno escrevem na mesma ficha, e sem
-- isto não dá para saber a autoria. created_by referencia users.id do
-- identity (sem FK: banco por serviço, ADR-013).
-- Linhas anteriores não guardaram o autor: o backfill assume o próprio aluno
-- (o caso comum até aqui) só para poder impor NOT NULL.
ALTER TABLE body_measurements ADD COLUMN created_by UUID;
UPDATE body_measurements SET created_by = student_id;
ALTER TABLE body_measurements ALTER COLUMN created_by SET NOT NULL;

ALTER TABLE bioimpedance_records ADD COLUMN created_by UUID;
UPDATE bioimpedance_records SET created_by = student_id;
ALTER TABLE bioimpedance_records ALTER COLUMN created_by SET NOT NULL;

ALTER TABLE progress_photos ADD COLUMN created_by UUID;
UPDATE progress_photos SET created_by = student_id;
ALTER TABLE progress_photos ALTER COLUMN created_by SET NOT NULL;
