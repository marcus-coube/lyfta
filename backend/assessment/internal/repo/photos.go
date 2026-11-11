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

// photoColumns é a projeção comum das leituras de foto de evolução.
const photoColumns = `id, student_id, taken_at, pose, media_key, COALESCE(notes, ''), created_by, created_at`

// PhotoRepo dá acesso às fotos de evolução (ADR-012 §2).
type PhotoRepo struct {
	pool *pgxpool.Pool
}

// NewPhotoRepo cria um PhotoRepo sobre o pool informado.
func NewPhotoRepo(pool *pgxpool.Pool) *PhotoRepo {
	return &PhotoRepo{pool: pool}
}

// Create grava uma foto de evolução. media_key já chega validada pelo
// handler (dentro da pasta do aluno, ADR-009) — o repositório só persiste.
func (r *PhotoRepo) Create(ctx context.Context, p domain.ProgressPhoto) (domain.ProgressPhoto, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.ProgressPhoto{}, fmt.Errorf("repo: gerar id da foto: %w", err)
	}
	p.ID = id.String()

	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO progress_photos (id, tenant_id, student_id, taken_at, pose, media_key, notes, created_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			RETURNING created_at`
		return tx.QueryRow(ctx, q,
			p.ID, p.TenantID, p.StudentID, p.TakenAt, string(p.Pose), p.MediaKey, nullString(p.Notes), p.CreatedBy,
		).Scan(&p.CreatedAt)
	})
	if err != nil {
		return domain.ProgressPhoto{}, fmt.Errorf("repo: criar foto: %w", err)
	}
	return p, nil
}

// List devolve as fotos do aluno, mais recentes primeiro.
func (r *PhotoRepo) List(ctx context.Context, tenantID, studentID string, cursorAt *time.Time, cursorID string, limit int) (items []domain.ProgressPhoto, hasMore bool, err error) {
	if limit <= 0 || limit > maxAssessmentPageSize {
		limit = maxAssessmentPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `SELECT ` + photoColumns + `
			FROM progress_photos
			WHERE student_id = $1
			  AND ($2::date IS NULL OR (taken_at, id) < ($2::date, $3::uuid))
			ORDER BY taken_at DESC, id DESC
			LIMIT $4`
		rows, queryErr := tx.Query(ctx, q, studentID, cursorAt, nullString(cursorID), limit+1)
		if queryErr != nil {
			return queryErr
		}
		defer rows.Close()
		for rows.Next() {
			var p domain.ProgressPhoto
			var pose string
			if err := rows.Scan(&p.ID, &p.StudentID, &p.TakenAt, &pose, &p.MediaKey, &p.Notes, &p.CreatedBy, &p.CreatedAt); err != nil {
				return err
			}
			p.Pose = domain.Pose(pose)
			p.TenantID = tenantID
			items = append(items, p)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar fotos: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Delete apaga uma foto do aluno. O objeto no storage não é removido aqui —
// é limpeza física, fora do escopo da P2.3 (dívida anotada).
func (r *PhotoRepo) Delete(ctx context.Context, tenantID, studentID, id string) error {
	var affected int64
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM progress_photos WHERE id = $1 AND student_id = $2`, id, studentID)
		if err != nil {
			return err
		}
		affected = tag.RowsAffected()
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: apagar foto: %w", err)
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}

// Count devolve o total de fotos do aluno — o resumo do coach (P2.3) só
// precisa da contagem, não da lista inteira.
func (r *PhotoRepo) Count(ctx context.Context, tenantID, studentID string) (int, error) {
	var n int
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT count(*) FROM progress_photos WHERE student_id = $1`, studentID).Scan(&n)
	})
	if err != nil {
		return 0, fmt.Errorf("repo: contar fotos: %w", err)
	}
	return n, nil
}
