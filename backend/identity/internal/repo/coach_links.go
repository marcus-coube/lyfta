package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrInvalidLink é devolvido por Reassign quando o aluno ou o coach alvo não
// servem para o vínculo (ADR-016 §1): o handler responde 422.
var ErrInvalidLink = errors.New("repo: aluno ou professor inválido para o vínculo")

// CoachLinkRepo dá acesso a coach_students (ADR-016, P4.7). Sempre dentro do
// tenant setado (RLS).
type CoachLinkRepo struct {
	pool *pgxpool.Pool
}

// NewCoachLinkRepo cria um CoachLinkRepo sobre o pool informado.
func NewCoachLinkRepo(pool *pgxpool.Pool) *CoachLinkRepo {
	return &CoachLinkRepo{pool: pool}
}

// Reassign troca o professor do aluno. O alvo precisa ser um aluno não
// excluído do tenant e o coach um usuário `active` com papel coach|owner;
// senão ErrInvalidLink. Cria o vínculo se o aluno ainda não tinha.
func (r *CoachLinkRepo) Reassign(ctx context.Context, tenantID, studentID, coachID, assignedBy string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var okStudent, okCoach bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM users u
			               JOIN user_roles r ON r.user_id = u.id AND r.role = 'student'
			               WHERE u.id = $1 AND u.status IN ('invited', 'active', 'inactive', 'disabled')),
			       EXISTS (SELECT 1 FROM users u
			               JOIN user_roles r ON r.user_id = u.id AND r.role IN ('coach', 'owner')
			               WHERE u.id = $2 AND u.status = 'active')`,
			studentID, coachID).Scan(&okStudent, &okCoach); err != nil {
			return err
		}
		if !okStudent || !okCoach {
			return ErrInvalidLink
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO coach_students (tenant_id, student_id, coach_id, assigned_by)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (tenant_id, student_id)
			DO UPDATE SET coach_id = EXCLUDED.coach_id, assigned_by = EXCLUDED.assigned_by, assigned_at = now()`,
			tenantID, studentID, coachID, assignedBy)
		return err
	})
	if err == ErrInvalidLink {
		return err
	}
	if err != nil {
		return fmt.Errorf("repo: reatribuir professor: %w", err)
	}
	return nil
}

// StudentIDs devolve os alunos (não excluídos) vinculados ao coach.
func (r *CoachLinkRepo) StudentIDs(ctx context.Context, tenantID, coachID string) ([]string, error) {
	ids := []string{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT cs.student_id::text FROM coach_students cs
			JOIN users u ON u.id = cs.student_id
			WHERE cs.coach_id = $1 AND u.status NOT IN ('deleting', 'deleted')
			ORDER BY cs.student_id`, coachID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				return err
			}
			ids = append(ids, id)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar alunos do professor: %w", err)
	}
	return ids, nil
}

// CoachOf devolve o professor atual do aluno, ou ErrNotFound.
func (r *CoachLinkRepo) CoachOf(ctx context.Context, tenantID, studentID string) (string, error) {
	var coachID string
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			SELECT cs.coach_id::text FROM coach_students cs
			JOIN users u ON u.id = cs.student_id
			WHERE cs.student_id = $1 AND u.status NOT IN ('deleting', 'deleted')`, studentID).Scan(&coachID)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		return err
	})
	if err == ErrNotFound {
		return "", err
	}
	if err != nil {
		return "", fmt.Errorf("repo: buscar professor do aluno: %w", err)
	}
	return coachID, nil
}
