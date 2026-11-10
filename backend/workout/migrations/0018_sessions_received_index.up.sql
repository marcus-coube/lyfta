-- Índice para "último treino por aluno" em lote (POST /v1/students/overview,
-- P5.4): MAX(received_at) por aluno sem varrer o histórico inteiro. Usa
-- received_at (carimbo do servidor, ADR-003), não started_at.
CREATE INDEX idx_workout_sessions_student_received
    ON workout_sessions (tenant_id, student_id, received_at DESC);
