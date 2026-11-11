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

// maxAssessmentPageSize é o teto de itens por página nas três listagens do
// serviço (P2.3): poucas dezenas de registros por aluno na prática, mas o
// cliente não decide o tamanho da página sozinho.
const maxAssessmentPageSize = 50

// measurementColumns é a projeção comum das leituras de medida.
const measurementColumns = `
	id, student_id, measured_at, weight_kg, height_cm, neck_cm, shoulder_cm,
	chest_cm, waist_cm, abdomen_cm, hip_cm, arm_l_cm, arm_r_cm, thigh_l_cm,
	thigh_r_cm, calf_l_cm, calf_r_cm, COALESCE(notes, ''), created_by, created_at`

// MeasurementRepo dá acesso às medidas corporais (P2.3). Toda operação passa
// por WithTenant: `app.tenant_id` é setado na transação antes de qualquer
// SELECT/INSERT/DELETE (ADR-001 §2).
type MeasurementRepo struct {
	pool *pgxpool.Pool
}

// NewMeasurementRepo cria um MeasurementRepo sobre o pool informado.
func NewMeasurementRepo(pool *pgxpool.Pool) *MeasurementRepo {
	return &MeasurementRepo{pool: pool}
}

// Create grava uma medida. studentID já vem resolvido pelo handler — pela
// claim (aluno) ou pela URL (coach) — e o RLS confere que tenant_id bate com
// a sessão.
func (r *MeasurementRepo) Create(ctx context.Context, m domain.BodyMeasurement) (domain.BodyMeasurement, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.BodyMeasurement{}, fmt.Errorf("repo: gerar id da medida: %w", err)
	}
	m.ID = id.String()

	err = WithTenant(ctx, r.pool, m.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO body_measurements (id, tenant_id, student_id, measured_at,
				weight_kg, height_cm, neck_cm, shoulder_cm, chest_cm, waist_cm,
				abdomen_cm, hip_cm, arm_l_cm, arm_r_cm, thigh_l_cm, thigh_r_cm,
				calf_l_cm, calf_r_cm, notes, created_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)
			RETURNING created_at`
		return tx.QueryRow(ctx, q,
			m.ID, m.TenantID, m.StudentID, m.MeasuredAt,
			m.WeightKg, m.HeightCm, m.NeckCm, m.ShoulderCm, m.ChestCm, m.WaistCm,
			m.AbdomenCm, m.HipCm, m.ArmLCm, m.ArmRCm, m.ThighLCm, m.ThighRCm,
			m.CalfLCm, m.CalfRCm, nullString(m.Notes), m.CreatedBy,
		).Scan(&m.CreatedAt)
	})
	if err != nil {
		return domain.BodyMeasurement{}, fmt.Errorf("repo: criar medida: %w", err)
	}
	return m, nil
}

// List devolve as medidas do aluno, mais recentes primeiro (cursor keyset por
// measured_at, id — duas medidas no mesmo dia não empatam).
func (r *MeasurementRepo) List(ctx context.Context, tenantID, studentID string, cursorAt *time.Time, cursorID string, limit int) (items []domain.BodyMeasurement, hasMore bool, err error) {
	if limit <= 0 || limit > maxAssessmentPageSize {
		limit = maxAssessmentPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `SELECT ` + measurementColumns + `
			FROM body_measurements
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
			var m domain.BodyMeasurement
			if err := rows.Scan(&m.ID, &m.StudentID, &m.MeasuredAt, &m.WeightKg, &m.HeightCm,
				&m.NeckCm, &m.ShoulderCm, &m.ChestCm, &m.WaistCm, &m.AbdomenCm, &m.HipCm,
				&m.ArmLCm, &m.ArmRCm, &m.ThighLCm, &m.ThighRCm, &m.CalfLCm, &m.CalfRCm,
				&m.Notes, &m.CreatedBy, &m.CreatedAt); err != nil {
				return err
			}
			m.TenantID = tenantID
			items = append(items, m)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar medidas: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Delete apaga uma medida do aluno. Não encontrar — id de outro aluno, de
// outro tenant, ou inexistente — devolve ErrNotFound; o handler não distingue
// os três casos (não vazar existência de dado de outro aluno).
func (r *MeasurementRepo) Delete(ctx context.Context, tenantID, studentID, id string) error {
	var affected int64
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM body_measurements WHERE id = $1 AND student_id = $2`, id, studentID)
		if err != nil {
			return err
		}
		affected = tag.RowsAffected()
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: apagar medida: %w", err)
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}
