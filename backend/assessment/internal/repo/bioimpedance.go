package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
)

// bioimpedanceColumns é a projeção comum das leituras de bioimpedância.
const bioimpedanceColumns = `
	id, student_id, measured_at, body_fat_pct, muscle_mass_kg, visceral_fat,
	body_water_pct, bone_mass_kg, bmr_kcal, COALESCE(notes, ''), created_at`

// BioimpedanceRepo dá acesso às leituras de bioimpedância digitadas
// (ADR-012 §2). Mesmo padrão de MeasurementRepo: um arquivo por agregado.
type BioimpedanceRepo struct {
	pool *pgxpool.Pool
}

// NewBioimpedanceRepo cria um BioimpedanceRepo sobre o pool informado.
func NewBioimpedanceRepo(pool *pgxpool.Pool) *BioimpedanceRepo {
	return &BioimpedanceRepo{pool: pool}
}

// Create grava uma leitura de bioimpedância.
func (r *BioimpedanceRepo) Create(ctx context.Context, b domain.BioimpedanceRecord) (domain.BioimpedanceRecord, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.BioimpedanceRecord{}, fmt.Errorf("repo: gerar id da bioimpedância: %w", err)
	}
	b.ID = id.String()

	err = WithTenant(ctx, r.pool, b.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO bioimpedance_records (id, tenant_id, student_id, measured_at,
				body_fat_pct, muscle_mass_kg, visceral_fat, body_water_pct, bone_mass_kg,
				bmr_kcal, notes)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			RETURNING created_at`
		return tx.QueryRow(ctx, q,
			b.ID, b.TenantID, b.StudentID, b.MeasuredAt,
			b.BodyFatPct, b.MuscleMassKg, b.VisceralFat, b.BodyWaterPct, b.BoneMassKg,
			b.BMRKcal, nullString(b.Notes),
		).Scan(&b.CreatedAt)
	})
	if err != nil {
		return domain.BioimpedanceRecord{}, fmt.Errorf("repo: criar bioimpedância: %w", err)
	}
	return b, nil
}

// List devolve as leituras do aluno, mais recentes primeiro.
func (r *BioimpedanceRepo) List(ctx context.Context, tenantID, studentID string, cursorAt *time.Time, cursorID string, limit int) (items []domain.BioimpedanceRecord, hasMore bool, err error) {
	if limit <= 0 || limit > maxAssessmentPageSize {
		limit = maxAssessmentPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `SELECT ` + bioimpedanceColumns + `
			FROM bioimpedance_records
			WHERE student_id = $1
			  AND ($2::date IS NULL OR (measured_at, id) < ($2::date, $3::uuid))
			ORDER BY measured_at DESC, id DESC
			LIMIT $4`
		rows, queryErr := tx.Query(ctx, q, studentID, cursorAt, nullString(cursorID), limit+1)
		if queryErr != nil {
			return queryErr
		}
		defer rows.Close()
		for rows.Next() {
			var b domain.BioimpedanceRecord
			if err := rows.Scan(&b.ID, &b.StudentID, &b.MeasuredAt, &b.BodyFatPct,
				&b.MuscleMassKg, &b.VisceralFat, &b.BodyWaterPct, &b.BoneMassKg,
				&b.BMRKcal, &b.Notes, &b.CreatedAt); err != nil {
				return err
			}
			b.TenantID = tenantID
			items = append(items, b)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar bioimpedância: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Delete apaga uma leitura de bioimpedância do aluno.
func (r *BioimpedanceRepo) Delete(ctx context.Context, tenantID, studentID, id string) error {
	var affected int64
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM bioimpedance_records WHERE id = $1 AND student_id = $2`, id, studentID)
		if err != nil {
			return err
		}
		affected = tag.RowsAffected()
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: apagar bioimpedância: %w", err)
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}
