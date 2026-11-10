-- Modelos de treino (ADR-018, P6.1): um modelo é um workout_plan com
-- kind='template' e sem aluno. Atribuir copia a árvore para um plano novo do
-- aluno (kind='assigned'); a cópia guarda só a procedência, sem vínculo vivo.
ALTER TABLE workout_plans
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'assigned'
        CHECK (kind IN ('assigned', 'template')),
    ADD COLUMN description TEXT NOT NULL DEFAULT '',
    -- Procedência da cópia. SET NULL só para o caso de um modelo ser removido
    -- algum dia; hoje modelo é arquivado, nunca apagado.
    ADD COLUMN source_template_id UUID REFERENCES workout_plans(id) ON DELETE SET NULL,
    -- Versão do modelo que gerou o conteúdo atual do plano (reaplicar atualiza).
    ADD COLUMN source_version_no INTEGER CHECK (source_version_no > 0),
    -- O coach mexeu no plano depois de aplicar/reaplicar o modelo: reaplicar
    -- vai descartar esses ajustes (ADR-018, Consequências).
    ADD COLUMN edited_after_source BOOLEAN NOT NULL DEFAULT FALSE,
    ALTER COLUMN student_id DROP NOT NULL,
    ADD CONSTRAINT workout_plans_kind_student
        CHECK ((kind = 'assigned') = (student_id IS NOT NULL));

CREATE INDEX idx_workout_plans_kind_updated
    ON workout_plans (tenant_id, kind, updated_at DESC, id DESC);
CREATE INDEX idx_workout_plans_source_template
    ON workout_plans (tenant_id, source_template_id) WHERE source_template_id IS NOT NULL;
