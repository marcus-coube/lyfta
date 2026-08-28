package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// PlanRepo grava e lê a árvore do template (ADR-004 §1):
// plano → versão → dia → bloco → exercício do bloco → sets prescritos.
// Escrever em uma versão já publicada é recusado pelo próprio banco
// (triggers da migration 0012), não só por regra de aplicação.
type PlanRepo struct {
	pool *pgxpool.Pool
}

// NewPlanRepo cria um PlanRepo sobre o pool informado.
func NewPlanRepo(pool *pgxpool.Pool) *PlanRepo {
	return &PlanRepo{pool: pool}
}

// CreatePlan cria o template do aluno em rascunho.
func (r *PlanRepo) CreatePlan(ctx context.Context, p domain.Plan) (domain.Plan, error) {
	id, err := newID("plano")
	if err != nil {
		return domain.Plan{}, err
	}
	p.ID = id
	if p.Status == "" {
		p.Status = domain.PlanStatusDraft
	}

	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_plans (id, tenant_id, student_id, coach_id, title, status)
			VALUES ($1, $2, $3, $4, $5, $6)
			RETURNING created_at, updated_at`
		return tx.QueryRow(ctx, q,
			p.ID, p.TenantID, p.StudentID, p.CoachID, p.Title, string(p.Status),
		).Scan(&p.CreatedAt, &p.UpdatedAt)
	})
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: criar plano: %w", err)
	}
	return p, nil
}

// CreateVersion abre uma versão nova do plano em rascunho (published_at NULL).
// O número da versão é o próximo da sequência do plano.
func (r *PlanRepo) CreateVersion(ctx context.Context, tenantID, planID string) (domain.PlanVersion, error) {
	id, err := newID("versão do plano")
	if err != nil {
		return domain.PlanVersion{}, err
	}
	v := domain.PlanVersion{ID: id, TenantID: tenantID, PlanID: planID}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_plan_versions (id, tenant_id, plan_id, version_no)
			VALUES ($1, $2, $3,
			        (SELECT COALESCE(MAX(version_no), 0) + 1
			         FROM workout_plan_versions WHERE plan_id = $3))
			RETURNING version_no, created_at`
		return tx.QueryRow(ctx, q, v.ID, v.TenantID, v.PlanID).Scan(&v.VersionNo, &v.CreatedAt)
	})
	if err != nil {
		return domain.PlanVersion{}, fmt.Errorf("repo: criar versão do plano: %w", err)
	}
	return v, nil
}

// Publish marca a versão como publicada. É o último UPDATE que a versão
// aceita: dali em diante ela e sua árvore ficam imutáveis (ADR-004 §1).
func (r *PlanRepo) Publish(ctx context.Context, tenantID, versionID string) (time.Time, error) {
	var publishedAt time.Time
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE workout_plan_versions SET published_at = now()
			WHERE id = $1
			RETURNING published_at`
		return tx.QueryRow(ctx, q, versionID).Scan(&publishedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrNotFound
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("repo: publicar versão: %w", err)
	}
	return publishedAt, nil
}

// AddDay acrescenta um dia (A/B/C…) à versão.
func (r *PlanRepo) AddDay(ctx context.Context, d domain.Day) (domain.Day, error) {
	id, err := newID("dia")
	if err != nil {
		return domain.Day{}, err
	}
	d.ID = id

	err = WithTenant(ctx, r.pool, d.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_days (id, tenant_id, plan_version_id, label, position, title)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, d.ID, d.TenantID, d.PlanVersionID, d.Label, d.Position, d.Title)
		return execErr
	})
	if err != nil {
		return domain.Day{}, fmt.Errorf("repo: criar dia: %w", err)
	}
	return d, nil
}

// AddBlock acrescenta um bloco ao dia (straight, superset, circuito…).
func (r *PlanRepo) AddBlock(ctx context.Context, b domain.Block) (domain.Block, error) {
	id, err := newID("bloco")
	if err != nil {
		return domain.Block{}, err
	}
	b.ID = id
	if b.BlockType == "" {
		b.BlockType = domain.BlockTypeStraight
	}

	err = WithTenant(ctx, r.pool, b.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_blocks (id, tenant_id, day_id, position, block_type, rest_seconds)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, b.ID, b.TenantID, b.DayID, b.Position, string(b.BlockType), b.RestSeconds)
		return execErr
	})
	if err != nil {
		return domain.Block{}, fmt.Errorf("repo: criar bloco: %w", err)
	}
	return b, nil
}

// AddBlockExercise coloca um exercício numa posição do bloco.
func (r *PlanRepo) AddBlockExercise(ctx context.Context, be domain.BlockExercise) (domain.BlockExercise, error) {
	id, err := newID("exercício do bloco")
	if err != nil {
		return domain.BlockExercise{}, err
	}
	be.ID = id

	err = WithTenant(ctx, r.pool, be.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO block_exercises (id, tenant_id, block_id, exercise_id, position, notes)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, be.ID, be.TenantID, be.BlockID, be.ExerciseID, be.Position, be.Notes)
		return execErr
	})
	if err != nil {
		return domain.BlockExercise{}, fmt.Errorf("repo: criar exercício do bloco: %w", err)
	}
	return be, nil
}

// AddPrescribedSet grava a prescrição estruturada de uma série (ADR-012 §4).
func (r *PlanRepo) AddPrescribedSet(ctx context.Context, s domain.PrescribedSet) (domain.PrescribedSet, error) {
	id, err := newID("set prescrito")
	if err != nil {
		return domain.PrescribedSet{}, err
	}
	s.ID = id

	err = WithTenant(ctx, r.pool, s.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO prescribed_sets (id, tenant_id, block_exercise_id, set_no, reps_min, reps_max,
			                             target_load_kg, target_unit, target_value, rest_seconds, tempo)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`
		var unit any
		if s.TargetUnit != nil {
			unit = string(*s.TargetUnit)
		}
		_, execErr := tx.Exec(ctx, q,
			s.ID, s.TenantID, s.BlockExerciseID, s.SetNo, s.RepsMin, s.RepsMax,
			s.TargetLoadKg, unit, s.TargetValue, s.RestSeconds, nullString(s.Tempo),
		)
		return execErr
	})
	if err != nil {
		return domain.PrescribedSet{}, fmt.Errorf("repo: criar set prescrito: %w", err)
	}
	return s, nil
}

// GetVersionTree lê a versão inteira montada — dias, blocos, exercícios e
// sets — em uma transação só. É o formato que vira snapshot da sessão
// (ADR-004 §2) e a base da tela de treino do dia.
//
// Uma query por nível, ordenada por posição: a árvore é pequena (um plano tem
// dezenas de linhas, não milhares) e assim cada nível é remontado em memória
// sem o produto cartesiano de um join único.
func (r *PlanRepo) GetVersionTree(ctx context.Context, tenantID, versionID string) ([]domain.Day, error) {
	var days []domain.Day

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		daysByID := map[string]*domain.Day{}
		const qDays = `
			SELECT id, tenant_id, plan_version_id, label, position, title
			FROM workout_days WHERE plan_version_id = $1 ORDER BY position`
		rows, err := tx.Query(ctx, qDays, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var d domain.Day
			if err := rows.Scan(&d.ID, &d.TenantID, &d.PlanVersionID, &d.Label, &d.Position, &d.Title); err != nil {
				rows.Close()
				return err
			}
			days = append(days, d)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if len(days) == 0 {
			return nil
		}
		for i := range days {
			daysByID[days[i].ID] = &days[i]
		}

		blocksByID := map[string]*domain.Block{}
		const qBlocks = `
			SELECT b.id, b.tenant_id, b.day_id, b.position, b.block_type, b.rest_seconds
			FROM workout_blocks b
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position`
		rows, err = tx.Query(ctx, qBlocks, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var b domain.Block
			if err := rows.Scan(&b.ID, &b.TenantID, &b.DayID, &b.Position, &b.BlockType, &b.RestSeconds); err != nil {
				rows.Close()
				return err
			}
			day := daysByID[b.DayID]
			day.Blocks = append(day.Blocks, b)
			blocksByID[b.ID] = &day.Blocks[len(day.Blocks)-1]
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		exercisesByID := map[string]*domain.BlockExercise{}
		const qBlockExercises = `
			SELECT be.id, be.tenant_id, be.block_id, be.exercise_id, be.position, be.notes
			FROM block_exercises be
			JOIN workout_blocks b ON b.id = be.block_id
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position, be.position`
		rows, err = tx.Query(ctx, qBlockExercises, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var be domain.BlockExercise
			if err := rows.Scan(&be.ID, &be.TenantID, &be.BlockID, &be.ExerciseID, &be.Position, &be.Notes); err != nil {
				rows.Close()
				return err
			}
			block := blocksByID[be.BlockID]
			block.Exercises = append(block.Exercises, be)
			exercisesByID[be.ID] = &block.Exercises[len(block.Exercises)-1]
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		const qSets = `
			SELECT ps.id, ps.tenant_id, ps.block_exercise_id, ps.set_no, ps.reps_min, ps.reps_max,
			       ps.target_load_kg, ps.target_unit, ps.target_value, ps.rest_seconds, COALESCE(ps.tempo, '')
			FROM prescribed_sets ps
			JOIN block_exercises be ON be.id = ps.block_exercise_id
			JOIN workout_blocks b ON b.id = be.block_id
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position, be.position, ps.set_no`
		rows, err = tx.Query(ctx, qSets, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var s domain.PrescribedSet
			if err := rows.Scan(&s.ID, &s.TenantID, &s.BlockExerciseID, &s.SetNo, &s.RepsMin, &s.RepsMax,
				&s.TargetLoadKg, &s.TargetUnit, &s.TargetValue, &s.RestSeconds, &s.Tempo); err != nil {
				rows.Close()
				return err
			}
			be := exercisesByID[s.BlockExerciseID]
			be.Sets = append(be.Sets, s)
		}
		rows.Close()
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: ler árvore da versão: %w", err)
	}
	return days, nil
}

func newID(what string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("repo: gerar id de %s: %w", what, err)
	}
	return id.String(), nil
}
