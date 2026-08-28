-- Índices que o contrato offline do P1.5 (ADR-003 §4) exige, e que nenhuma
-- consulta anterior precisava:
--   1. revisão: "este log foi corrigido depois?" é NOT EXISTS por client_id
--      (ADR-003 §5) — sem índice, cada leitura de carga anterior varre a
--      tabela inteira de logs do tenant.
--   2. pull incremental: a biblioteca é varrida por (updated_at, id), e o
--      índice tem de cobrir o global (tenant_id NULL) junto com o do tenant,
--      então NÃO começa por tenant_id — é o único índice do serviço assim, de
--      propósito.
CREATE INDEX idx_workout_set_logs_revises ON workout_set_logs (tenant_id, revises)
    WHERE revises IS NOT NULL;

CREATE INDEX idx_exercises_sync ON exercises (updated_at, id);
