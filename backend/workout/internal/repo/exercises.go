package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// ExerciseRepo dá acesso à biblioteca de exercícios (ADR-010). Toda operação
// passa por WithTenant: `app.tenant_id` é setado na transação antes de
// qualquer SELECT/INSERT (ADR-001 §2).
type ExerciseRepo struct {
	pool *pgxpool.Pool
}

// NewExerciseRepo cria um ExerciseRepo sobre o pool informado.
func NewExerciseRepo(pool *pgxpool.Pool) *ExerciseRepo {
	return &ExerciseRepo{pool: pool}
}

// Create insere um exercício **do tenant** (ADR-010 §3). A biblioteca global
// (tenant_id NULL) não passa por aqui: as policies de escrita da tabela só
// aceitam linhas do próprio tenant, e os globais entram por seed
// administrativo — tentar criar um global pela aplicação falha no RLS, de
// propósito.
func (r *ExerciseRepo) Create(ctx context.Context, e domain.Exercise) (domain.Exercise, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: gerar id do exercício: %w", err)
	}
	e.ID = id.String()
	if e.Level == "" {
		e.Level = domain.LevelBeginner
	}
	if e.Status == "" {
		e.Status = domain.ExerciseStatusActive
	}

	err = WithTenant(ctx, r.pool, e.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO exercises (id, tenant_id, name, primary_muscle, equipment, level,
			                       media_url, media_type, created_by, status)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
			RETURNING created_at, updated_at`
		return tx.QueryRow(ctx, q,
			e.ID, e.TenantID, e.Name, e.PrimaryMuscle, e.Equipment, string(e.Level),
			nullString(e.MediaURL), nullString(string(e.MediaType)), nullString(e.CreatedBy),
			string(e.Status),
		).Scan(&e.CreatedAt, &e.UpdatedAt)
	})
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: criar exercício: %w", err)
	}
	return e, nil
}

// GetByID lê um exercício visível para o tenant — o próprio ou um global
// (policy de leitura dupla da migration 0001).
func (r *ExerciseRepo) GetByID(ctx context.Context, tenantID, exerciseID string) (domain.Exercise, error) {
	var e domain.Exercise
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT id, COALESCE(tenant_id::text, ''), name, primary_muscle, equipment, level,
			       COALESCE(media_url, ''), COALESCE(media_type, ''), COALESCE(created_by::text, ''),
			       status, created_at, updated_at
			FROM exercises
			WHERE id = $1`
		return tx.QueryRow(ctx, q, exerciseID).Scan(
			&e.ID, &e.TenantID, &e.Name, &e.PrimaryMuscle, &e.Equipment, &e.Level,
			&e.MediaURL, &e.MediaType, &e.CreatedBy, &e.Status, &e.CreatedAt, &e.UpdatedAt,
		)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Exercise{}, ErrNotFound
	}
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: buscar exercício: %w", err)
	}
	return e, nil
}

// nullString converte string vazia em NULL — as colunas opcionais do schema
// (media_url, created_by…) distinguem "sem valor" de string vazia.
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}
