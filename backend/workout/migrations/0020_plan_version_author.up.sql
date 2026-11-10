-- Autor da publicação (P6.2): quem congelou a versão — o coach que publicou,
-- atribuiu ou reaplicou o modelo. NULL em versões anteriores a esta migration
-- e em rascunho. A coluna entra no mesmo UPDATE que grava published_at, o
-- último que o trigger de imutabilidade (0012) aceita. Referência por UUID
-- sem FK: users vive no identity (ADR-013 §2).
ALTER TABLE workout_plan_versions ADD COLUMN published_by UUID;
