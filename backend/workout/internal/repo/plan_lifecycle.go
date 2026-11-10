package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

var (
	// ErrPlanIsActive: arquivar o plano ativo do aluno exige ativar outro antes
	// (senão o aluno ficaria sem treino sem o coach ter decidido isso).
	ErrPlanIsActive = errors.New("repo: plano é o ativo do aluno")
	// ErrPlanNotPublished: só plano com versão publicada entra na rotação.
	ErrPlanNotPublished = errors.New("repo: plano sem versão publicada")
)

// ListVersionSummaries devolve o histórico de versões do plano, da mais
// recente para a mais antiga, com autor e contagem de dias/exercícios.
func (r *PlanRepo) ListVersionSummaries(ctx context.Context, tenantID, planID string) ([]domain.VersionSummary, error) {
	var out []domain.VersionSummary
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT v.id, v.tenant_id, v.plan_id, v.version_no, v.published_at, v.created_at,
			       COALESCE(v.published_by::text, ''),
			       (SELECT COUNT(*) FROM workout_days d WHERE d.plan_version_id = v.id),
			       (SELECT COUNT(*) FROM workout_days d
			          JOIN workout_blocks b ON b.day_id = d.id
			          JOIN block_exercises be ON be.block_id = b.id
			         WHERE d.plan_version_id = v.id)
			FROM workout_plan_versions v
			WHERE v.plan_id = $1
			ORDER BY v.version_no DESC`, planID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.VersionSummary
			if err := rows.Scan(&s.ID, &s.TenantID, &s.PlanID, &s.VersionNo, &s.PublishedAt, &s.CreatedAt,
				&s.PublishedBy, &s.DaysCount, &s.ExercisesCount); err != nil {
				return err
			}
			out = append(out, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar resumo de versões: %w", err)
	}
	return out, nil
}

// DuplicateParams é a cópia de um plano de aluno para o mesmo aluno ou outro.
type DuplicateParams struct {
	TenantID     string
	SourcePlanID string
	// StudentID é o aluno que recebe a cópia; CoachID, o autor dela (o
	// professor vinculado a esse aluno).
	StudentID string
	CoachID   string
}

// DuplicatePlan copia a versão mais recente do plano (o rascunho aberto, se
// houver; a última publicada caso contrário — o que o builder mostra) para um
// plano novo em rascunho, fora da rotação e sem procedência de modelo. Plano
// sem versão vira plano vazio. ErrNotFound se a origem não existe ou é modelo.
func (r *PlanRepo) DuplicatePlan(ctx context.Context, p DuplicateParams) (domain.Plan, error) {
	id, err := newID("plano")
	if err != nil {
		return domain.Plan{}, err
	}
	var dup domain.Plan
	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		var src domain.Plan
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT `+planColumns+` FROM workout_plans p WHERE p.id = $1`, p.SourcePlanID), &src); err != nil {
			return err
		}
		if src.Kind != domain.PlanKindAssigned {
			return pgx.ErrNoRows
		}
		var days []domain.Day
		var versionID string
		err := tx.QueryRow(ctx, `
			SELECT id FROM workout_plan_versions WHERE plan_id = $1
			ORDER BY version_no DESC LIMIT 1`, src.ID).Scan(&versionID)
		switch {
		case err == nil:
			if days, err = versionTreeTx(ctx, tx, versionID); err != nil {
				return err
			}
		case !errors.Is(err, pgx.ErrNoRows):
			return err
		}

		dup = domain.Plan{
			ID: id, TenantID: p.TenantID, StudentID: p.StudentID, CoachID: p.CoachID,
			Title: src.Title, Status: domain.PlanStatusDraft, Kind: domain.PlanKindAssigned,
		}
		if err := insertPlanTx(ctx, tx, &dup); err != nil {
			return err
		}
		if len(days) == 0 {
			return nil
		}
		_, err = replaceDraftTreeTx(ctx, tx, p.TenantID, dup.ID, days)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Plan{}, ErrNotFound
	}
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: duplicar plano: %w", err)
	}
	return dup, nil
}

// ArchivePlan arquiva um plano de aluno. Idempotente (já arquivado = ok).
// ErrPlanIsActive se é o plano ativo do aluno; ErrNotFound se não existe ou é
// modelo (modelo tem a rota própria).
func (r *PlanRepo) ArchivePlan(ctx context.Context, tenantID, planID string) (domain.Plan, error) {
	var plan domain.Plan
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT `+planColumns+` FROM workout_plans p WHERE p.id = $1 FOR UPDATE`, planID), &plan); err != nil {
			return err
		}
		if plan.Kind != domain.PlanKindAssigned {
			return pgx.ErrNoRows
		}
		var active bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM student_plan_state WHERE student_id = $1 AND plan_id = $2)`,
			plan.StudentID, planID).Scan(&active); err != nil {
			return err
		}
		if active {
			return ErrPlanIsActive
		}
		if plan.Status == domain.PlanStatusArchived {
			return nil
		}
		plan.Status = domain.PlanStatusArchived
		return tx.QueryRow(ctx, `
			UPDATE workout_plans SET status = 'archived', updated_at = now() WHERE id = $1
			RETURNING updated_at`, planID).Scan(&plan.UpdatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Plan{}, ErrNotFound
	}
	if errors.Is(err, ErrPlanIsActive) {
		return domain.Plan{}, err
	}
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: arquivar plano: %w", err)
	}
	return plan, nil
}

// ActivatePlan põe o plano na rotação do aluno, na última versão publicada,
// com a rotação recomeçando no primeiro dia; o plano ativo anterior vira
// arquivado (um ativo por aluno, como no publish). Idempotente: já ativo
// devolve o estado atual sem reiniciar a rotação. ErrNotFound se o plano não
// é deste aluno; ErrPlanNotPublished se nunca foi publicado.
func (r *PlanRepo) ActivatePlan(ctx context.Context, tenantID, studentID, planID string) (domain.StudentPlanState, error) {
	var state domain.StudentPlanState
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var plan domain.Plan
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT `+planColumns+` FROM workout_plans p WHERE p.id = $1 FOR UPDATE`, planID), &plan); err != nil {
			return err
		}
		if plan.Kind != domain.PlanKindAssigned || plan.StudentID != studentID {
			return pgx.ErrNoRows
		}

		err := tx.QueryRow(ctx, `
			SELECT tenant_id, student_id, plan_id, active_version_id, next_day_id, last_session_at, updated_at
			FROM student_plan_state WHERE student_id = $1 AND plan_id = $2`, studentID, planID).Scan(
			&state.TenantID, &state.StudentID, &state.PlanID, &state.ActiveVersionID,
			&state.NextDayID, &state.LastSessionAt, &state.UpdatedAt)
		if err == nil {
			return nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}

		var versionID string
		if err := tx.QueryRow(ctx, `
			SELECT id FROM workout_plan_versions
			WHERE plan_id = $1 AND published_at IS NOT NULL
			ORDER BY version_no DESC LIMIT 1`, planID).Scan(&versionID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrPlanNotPublished
			}
			return err
		}
		var firstDay string
		if err := tx.QueryRow(ctx, `
			SELECT id FROM workout_days WHERE plan_version_id = $1 ORDER BY position LIMIT 1`, versionID).Scan(&firstDay); err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}

		if _, err := tx.Exec(ctx, `
			UPDATE workout_plans SET status = 'archived', updated_at = now()
			WHERE student_id = $1 AND id <> $2 AND status = 'published'`, studentID, planID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE workout_plans SET status = 'published', updated_at = now() WHERE id = $1`, planID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id, next_day_id)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (tenant_id, student_id) DO UPDATE
			SET plan_id = EXCLUDED.plan_id,
			    active_version_id = EXCLUDED.active_version_id,
			    next_day_id = EXCLUDED.next_day_id,
			    updated_at = now()
			RETURNING tenant_id, student_id, plan_id, active_version_id,
			          next_day_id, last_session_at, updated_at`,
			tenantID, studentID, planID, versionID, nullString(firstDay)).Scan(
			&state.TenantID, &state.StudentID, &state.PlanID, &state.ActiveVersionID,
			&state.NextDayID, &state.LastSessionAt, &state.UpdatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.StudentPlanState{}, ErrNotFound
	}
	if errors.Is(err, ErrPlanNotPublished) {
		return domain.StudentPlanState{}, err
	}
	if err != nil {
		return domain.StudentPlanState{}, fmt.Errorf("repo: ativar plano: %w", err)
	}
	return state, nil
}
