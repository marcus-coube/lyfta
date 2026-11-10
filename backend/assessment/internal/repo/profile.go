package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
)

// ProfileRepo dá acesso à anamnese do aluno (P5.3). Toda operação passa por
// WithTenant (ADR-001 §2).
type ProfileRepo struct {
	pool *pgxpool.Pool
}

// NewProfileRepo cria um ProfileRepo sobre o pool informado.
func NewProfileRepo(pool *pgxpool.Pool) *ProfileRepo {
	return &ProfileRepo{pool: pool}
}

// Get devolve a anamnese do aluno; ErrNotFound quando ainda não existe (o
// handler responde com o perfil vazio — não é erro para o cliente).
func (r *ProfileRepo) Get(ctx context.Context, tenantID, studentID string) (domain.StudentProfile, error) {
	p := domain.StudentProfile{TenantID: tenantID, StudentID: studentID}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT goal, COALESCE(goal_notes, ''), training_experience, weekly_target,
			       COALESCE(medical_notes, ''), COALESCE(coach_notes, ''), updated_at, updated_by
			FROM student_profiles WHERE student_id = $1`, studentID,
		).Scan(&p.Goal, &p.GoalNotes, &p.TrainingExperience, &p.WeeklyTarget,
			&p.MedicalNotes, &p.CoachNotes, &p.UpdatedAt, &p.UpdatedBy)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.StudentProfile{}, ErrNotFound
	}
	if err != nil {
		return domain.StudentProfile{}, fmt.Errorf("repo: ler anamnese: %w", err)
	}
	return p, nil
}

// Upsert grava objetivo, experiência e observações de saúde. Meta semanal e
// coach_notes são do coach: só são escritas quando coachPort — a porta do
// aluno nunca as toca, nem para sobrescrever com vazio.
func (r *ProfileRepo) Upsert(ctx context.Context, p domain.StudentProfile, coachPort bool) (domain.StudentProfile, error) {
	err := WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO student_profiles (tenant_id, student_id, goal, goal_notes,
				training_experience, weekly_target, medical_notes, coach_notes, updated_by)
			VALUES ($1, $2, $3, $4, $5, CASE WHEN $9 THEN $6::int END, $7, CASE WHEN $9 THEN $8 END, $10)
			ON CONFLICT (tenant_id, student_id) DO UPDATE SET
				goal = EXCLUDED.goal,
				goal_notes = EXCLUDED.goal_notes,
				training_experience = EXCLUDED.training_experience,
				weekly_target = CASE WHEN $9 THEN EXCLUDED.weekly_target ELSE student_profiles.weekly_target END,
				medical_notes = EXCLUDED.medical_notes,
				coach_notes = CASE WHEN $9 THEN EXCLUDED.coach_notes ELSE student_profiles.coach_notes END,
				updated_at = now(),
				updated_by = EXCLUDED.updated_by
			RETURNING goal, COALESCE(goal_notes, ''), training_experience, weekly_target,
				COALESCE(medical_notes, ''), COALESCE(coach_notes, ''), updated_at, updated_by`
		return tx.QueryRow(ctx, q, p.TenantID, p.StudentID, p.Goal, nullString(p.GoalNotes),
			p.TrainingExperience, p.WeeklyTarget, nullString(p.MedicalNotes), nullString(p.CoachNotes),
			coachPort, p.UpdatedBy,
		).Scan(&p.Goal, &p.GoalNotes, &p.TrainingExperience, &p.WeeklyTarget,
			&p.MedicalNotes, &p.CoachNotes, &p.UpdatedAt, &p.UpdatedBy)
	})
	if err != nil {
		return domain.StudentProfile{}, fmt.Errorf("repo: gravar anamnese: %w", err)
	}
	return p, nil
}
