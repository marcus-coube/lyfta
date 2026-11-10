package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// Modelos de treino (ADR-018, P6.1). Um modelo é um workout_plan com
// kind='template'; atribuir e reaplicar são cópias profundas da última versão
// **publicada**, sempre numa transação por plano de aluno.

var (
	// ErrTemplateNotPublished: o modelo ainda não tem versão publicada para copiar.
	ErrTemplateNotPublished = errors.New("repo: modelo sem versão publicada")
	// ErrNotRecipient: o plano não nasceu deste modelo.
	ErrNotRecipient = errors.New("repo: plano não pertence aos destinatários do modelo")
	// ErrPlanArchived: plano arquivado não é reaplicado (reativaria o plano
	// sem o coach ter pedido).
	ErrPlanArchived = errors.New("repo: plano arquivado")
)

// LatestPublishedVersion devolve a última versão publicada do plano; ErrNotFound
// se nunca foi publicado.
func (r *PlanRepo) LatestPublishedVersion(ctx context.Context, tenantID, planID string) (domain.PlanVersion, error) {
	return r.versionBy(ctx, tenantID, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions
		WHERE plan_id = $1 AND published_at IS NOT NULL
		ORDER BY version_no DESC LIMIT 1`, planID)
}

// TemplateFilter é a busca da biblioteca de modelos.
type TemplateFilter struct {
	Query string
	// Status: "" (ativos: rascunho e publicado), "archived" ou "all".
	Status string
	// Cursor keyset (updated_at, id), do mais recente para o mais antigo.
	CursorUpdatedAt *time.Time
	CursorID        string
	Limit           int
}

// ListTemplates lista os modelos do tenant, mais recentemente alterados
// primeiro, com contagens da última versão publicada.
func (r *PlanRepo) ListTemplates(ctx context.Context, tenantID string, f TemplateFilter) (items []domain.TemplateSummary, hasMore bool, err error) {
	limit := f.Limit
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT ` + planColumns + `,
			       COALESCE(v.latest_no, 0), COALESCE(v.published_no, 0), COALESCE(v.has_draft, FALSE),
			       COALESCE(pv.days, 0), COALESCE(pv.exercises, 0),
			       (SELECT count(*) FROM workout_plans c
			         WHERE c.source_template_id = p.id AND c.student_id <> $6::uuid)
			FROM workout_plans p
			LEFT JOIN LATERAL (
				SELECT MAX(version_no) AS latest_no,
				       MAX(version_no) FILTER (WHERE published_at IS NOT NULL) AS published_no,
				       bool_or(published_at IS NULL) AS has_draft
				FROM workout_plan_versions WHERE plan_id = p.id
			) v ON TRUE
			LEFT JOIN LATERAL (
				SELECT (SELECT count(*) FROM workout_days d WHERE d.plan_version_id = x.id) AS days,
				       (SELECT count(*) FROM block_exercises be
				          JOIN workout_blocks b ON b.id = be.block_id
				          JOIN workout_days d ON d.id = b.day_id
				         WHERE d.plan_version_id = x.id) AS exercises
				FROM workout_plan_versions x
				WHERE x.plan_id = p.id AND x.published_at IS NOT NULL
				ORDER BY x.version_no DESC LIMIT 1
			) pv ON TRUE
			WHERE p.kind = 'template'
			  AND ($1 = 'all' OR ($1 = 'archived' AND p.status = 'archived')
			       OR ($1 = '' AND p.status <> 'archived'))
			  AND ($2 = '' OR lyfta_search_norm(p.title) LIKE '%' || lyfta_search_norm($2) || '%')
			  AND ($3::timestamptz IS NULL OR (p.updated_at, p.id) < ($3::timestamptz, $4::uuid))
			ORDER BY p.updated_at DESC, p.id DESC
			LIMIT $5`
		rows, qErr := tx.Query(ctx, q, f.Status, escapeLike(f.Query), f.CursorUpdatedAt,
			nullString(f.CursorID), limit+1, AnonymousUserID)
		if qErr != nil {
			return qErr
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.TemplateSummary
			if err := rows.Scan(&s.ID, &s.TenantID, &s.StudentID, &s.CoachID, &s.Title, &s.Status,
				&s.Kind, &s.Description, &s.SourceTemplateID, &s.SourceVersionNo,
				&s.EditedAfterSource, &s.CreatedAt, &s.UpdatedAt,
				&s.LatestVersionNo, &s.PublishedVersionNo, &s.HasDraft,
				&s.DaysCount, &s.ExercisesCount, &s.AssignedCount); err != nil {
				return err
			}
			items = append(items, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar modelos: %w", err)
	}
	if len(items) > limit {
		items, hasMore = items[:limit], true
	}
	return items, hasMore, nil
}

// ArchiveTemplate arquiva o modelo (idempotente). ErrNotFound se o id não é de
// um modelo do tenant. Arquivar não afeta os planos já atribuídos (sem vínculo
// vivo, ADR-018 §2).
func (r *PlanRepo) ArchiveTemplate(ctx context.Context, tenantID, templateID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE workout_plans
			SET status = 'archived',
			    updated_at = CASE WHEN status = 'archived' THEN updated_at ELSE now() END
			WHERE id = $1 AND kind = 'template'`, templateID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("repo: arquivar modelo: %w", err)
	}
	return nil
}

// UnarchiveTemplate devolve o modelo à biblioteca (idempotente): volta como
// `published` se já teve versão publicada, `draft` caso contrário. ErrNotFound
// se o id não é de um modelo do tenant.
func (r *PlanRepo) UnarchiveTemplate(ctx context.Context, tenantID, templateID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE workout_plans p
			SET status = CASE WHEN EXISTS (
			        SELECT 1 FROM workout_plan_versions v
			        WHERE v.plan_id = p.id AND v.published_at IS NOT NULL
			    ) THEN 'published' ELSE 'draft' END,
			    updated_at = now()
			WHERE p.id = $1 AND p.kind = 'template' AND p.status = 'archived'`, templateID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			return nil
		}
		var exists bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM workout_plans WHERE id = $1 AND kind = 'template')`, templateID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return pgx.ErrNoRows
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("repo: desarquivar modelo: %w", err)
	}
	return nil
}

// AssignParams é a atribuição de um modelo a um aluno. Days é a árvore da
// versão publicada do modelo, lida uma vez pelo chamador e copiada para cada
// aluno (a versão é imutável, ADR-004 §1).
type AssignParams struct {
	TenantID string
	CoachID  string
	// ActorID é quem atribuiu (autor da versão publicada).
	ActorID         string
	StudentID       string
	Template        domain.Plan
	TemplateVersion domain.PlanVersion
	Days            []domain.Day
	// Publish já coloca o plano na rotação do aluno (como o publish do builder).
	Publish bool
}

// AssignTemplate cria, numa transação, um plano novo do aluno com cópia
// profunda do modelo (ADR-018 §2). Sem Publish o plano nasce rascunho (v1).
func (r *PlanRepo) AssignTemplate(ctx context.Context, p AssignParams) (domain.Plan, error) {
	id, err := newID("plano")
	if err != nil {
		return domain.Plan{}, err
	}
	plan := domain.Plan{
		ID: id, TenantID: p.TenantID, StudentID: p.StudentID, CoachID: p.CoachID,
		Title: p.Template.Title, Description: p.Template.Description,
		Status: domain.PlanStatusDraft, Kind: domain.PlanKindAssigned,
		SourceTemplateID: p.Template.ID, SourceVersionNo: p.TemplateVersion.VersionNo,
	}

	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		if err := insertPlanTx(ctx, tx, &plan); err != nil {
			return err
		}
		if _, err := replaceDraftTreeTx(ctx, tx, p.TenantID, plan.ID, p.Days); err != nil {
			return err
		}
		if p.Publish {
			if _, _, err := publishDraftTx(ctx, tx, p.TenantID, plan.ID, p.ActorID); err != nil {
				return err
			}
			plan.Status = domain.PlanStatusPublished
		}
		return nil
	})
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: atribuir modelo: %w", err)
	}
	return plan, nil
}

// ListRecipients devolve os planos de aluno que nasceram do modelo, com a
// marca de ativo. Planos de alunos já excluídos (titular anônimo) ficam de fora.
func (r *PlanRepo) ListRecipients(ctx context.Context, tenantID, templateID string) ([]domain.TemplateRecipient, error) {
	var out []domain.TemplateRecipient
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT `+planColumns+`, (s.plan_id IS NOT NULL)
			FROM workout_plans p
			LEFT JOIN student_plan_state s ON s.student_id = p.student_id AND s.plan_id = p.id
			WHERE p.source_template_id = $1 AND p.kind = 'assigned' AND p.student_id <> $2::uuid
			ORDER BY p.updated_at DESC, p.id DESC`, templateID, AnonymousUserID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var rc domain.TemplateRecipient
			if err := rows.Scan(&rc.ID, &rc.TenantID, &rc.StudentID, &rc.CoachID, &rc.Title, &rc.Status,
				&rc.Kind, &rc.Description, &rc.SourceTemplateID, &rc.SourceVersionNo,
				&rc.EditedAfterSource, &rc.CreatedAt, &rc.UpdatedAt, &rc.IsActive); err != nil {
				return err
			}
			out = append(out, rc)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar destinatários do modelo: %w", err)
	}
	return out, nil
}

// ReapplyParams é a reaplicação do modelo a um plano de aluno.
type ReapplyParams struct {
	TenantID string
	// ActorID é quem reaplicou (autor da versão publicada).
	ActorID         string
	PlanID          string
	Template        domain.Plan
	TemplateVersion domain.PlanVersion
	Days            []domain.Day
}

// ReapplyTemplate troca a árvore do rascunho do plano pela versão atual do
// modelo e publica como versão nova (ADR-018, Consequências): o histórico
// fica, os ajustes individuais do plano se perdem. Publicar reancora a rotação
// pelo rótulo do dia (nextDayForPublish). ErrNotFound, ErrNotRecipient ou
// ErrPlanArchived quando o plano não pode ser reaplicado.
func (r *PlanRepo) ReapplyTemplate(ctx context.Context, p ReapplyParams) (domain.PlanVersion, error) {
	var version domain.PlanVersion
	err := WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		var plan domain.Plan
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT `+planColumns+` FROM workout_plans p WHERE p.id = $1 FOR UPDATE`, p.PlanID), &plan); err != nil {
			return err
		}
		if plan.Kind != domain.PlanKindAssigned || plan.SourceTemplateID != p.Template.ID {
			return ErrNotRecipient
		}
		if plan.Status == domain.PlanStatusArchived {
			return ErrPlanArchived
		}
		if _, err := replaceDraftTreeTx(ctx, tx, p.TenantID, p.PlanID, p.Days); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE workout_plans SET source_version_no = $2, edited_after_source = FALSE, updated_at = now()
			WHERE id = $1`, p.PlanID, p.TemplateVersion.VersionNo); err != nil {
			return err
		}
		var err error
		version, _, err = publishDraftTx(ctx, tx, p.TenantID, p.PlanID, p.ActorID)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.PlanVersion{}, ErrNotFound
	}
	if errors.Is(err, ErrNotRecipient) || errors.Is(err, ErrPlanArchived) {
		return domain.PlanVersion{}, err
	}
	if err != nil {
		return domain.PlanVersion{}, fmt.Errorf("repo: reaplicar modelo: %w", err)
	}
	return version, nil
}

// SaveAsTemplateParams cria um modelo a partir de um plano de aluno.
type SaveAsTemplateParams struct {
	TenantID     string
	CoachID      string
	SourcePlanID string
	// Title vazio = título do plano de origem.
	Title string
}

// SaveAsTemplate copia a versão mais recente do plano (o rascunho aberto, se
// houver; a última publicada caso contrário — o que o builder mostra) para um
// modelo novo em rascunho, sem procedência: o modelo não "pertence" ao plano
// (ADR-018 §2). ErrNotFound se o plano não existe ou já é um modelo;
// IncompletePlanError{no_days} se não há nada a copiar.
func (r *PlanRepo) SaveAsTemplate(ctx context.Context, p SaveAsTemplateParams) (domain.Plan, error) {
	id, err := newID("modelo")
	if err != nil {
		return domain.Plan{}, err
	}
	var tpl domain.Plan
	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		var src domain.Plan
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT `+planColumns+` FROM workout_plans p WHERE p.id = $1`, p.SourcePlanID), &src); err != nil {
			return err
		}
		if src.Kind != domain.PlanKindAssigned {
			return pgx.ErrNoRows
		}
		var versionID string
		if err := tx.QueryRow(ctx, `
			SELECT id FROM workout_plan_versions WHERE plan_id = $1
			ORDER BY version_no DESC LIMIT 1`, src.ID).Scan(&versionID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return IncompletePlanError{Reason: "no_days"}
			}
			return err
		}
		days, err := versionTreeTx(ctx, tx, versionID)
		if err != nil {
			return err
		}
		if len(days) == 0 {
			return IncompletePlanError{Reason: "no_days"}
		}

		title := p.Title
		if title == "" {
			title = src.Title
		}
		tpl = domain.Plan{
			ID: id, TenantID: p.TenantID, CoachID: p.CoachID, Title: title,
			Status: domain.PlanStatusDraft, Kind: domain.PlanKindTemplate,
		}
		if err := insertPlanTx(ctx, tx, &tpl); err != nil {
			return err
		}
		_, err = replaceDraftTreeTx(ctx, tx, p.TenantID, tpl.ID, days)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Plan{}, ErrNotFound
	}
	var incomplete IncompletePlanError
	if errors.As(err, &incomplete) {
		return domain.Plan{}, err
	}
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: salvar plano como modelo: %w", err)
	}
	return tpl, nil
}
