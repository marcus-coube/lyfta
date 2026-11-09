package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
)

const injuryColumns = `id, student_id, body_region, description, since, resolved_at, created_by, created_at`

// InjuryRepo dá acesso às lesões e restrições do aluno (P5.3).
type InjuryRepo struct {
	pool *pgxpool.Pool
}

// NewInjuryRepo cria um InjuryRepo sobre o pool informado.
func NewInjuryRepo(pool *pgxpool.Pool) *InjuryRepo {
	return &InjuryRepo{pool: pool}
}

func scanInjury(row pgx.Row, tenantID string) (domain.StudentInjury, error) {
	var in domain.StudentInjury
	err := row.Scan(&in.ID, &in.StudentID, &in.BodyRegion, &in.Description, &in.Since,
		&in.ResolvedAt, &in.CreatedBy, &in.CreatedAt)
	in.TenantID = tenantID
	return in, err
}

// Create grava uma lesão.
func (r *InjuryRepo) Create(ctx context.Context, in domain.StudentInjury) (domain.StudentInjury, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.StudentInjury{}, fmt.Errorf("repo: gerar id da lesão: %w", err)
	}
	in.ID = id.String()
	err = WithTenant(ctx, r.pool, in.TenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO student_injuries (id, tenant_id, student_id, body_region, description, since, resolved_at, created_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			RETURNING created_at`,
			in.ID, in.TenantID, in.StudentID, in.BodyRegion, in.Description, in.Since, in.ResolvedAt, in.CreatedBy,
		).Scan(&in.CreatedAt)
	})
	if err != nil {
		return domain.StudentInjury{}, fmt.Errorf("repo: criar lesão: %w", err)
	}
	return in, nil
}

// List devolve as lesões do aluno: ativas primeiro, depois as resolvidas, da
// mais recente para a mais antiga. onlyActive filtra as resolvidas fora.
func (r *InjuryRepo) List(ctx context.Context, tenantID, studentID string, onlyActive bool) ([]domain.StudentInjury, error) {
	var items []domain.StudentInjury
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+injuryColumns+`
			FROM student_injuries
			WHERE student_id = $1 AND (NOT $2 OR resolved_at IS NULL)
			ORDER BY (resolved_at IS NOT NULL), created_at DESC, id DESC`, studentID, onlyActive)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			in, err := scanInjury(rows, tenantID)
			if err != nil {
				return err
			}
			items = append(items, in)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar lesões: %w", err)
	}
	return items, nil
}

// Update aplica mutate sobre a lesão (lida com FOR UPDATE) e grava. Lesão de
// outro aluno, de outro tenant ou inexistente: ErrNotFound. Se mutate falhar,
// nada é gravado e o erro volta como está.
func (r *InjuryRepo) Update(ctx context.Context, tenantID, studentID, id string, mutate func(*domain.StudentInjury) error) (domain.StudentInjury, error) {
	var out domain.StudentInjury
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		in, err := scanInjury(tx.QueryRow(ctx, `SELECT `+injuryColumns+`
			FROM student_injuries WHERE id = $1 AND student_id = $2 FOR UPDATE`, id, studentID), tenantID)
		if err != nil {
			return err
		}
		if err := mutate(&in); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE student_injuries SET body_region = $2, description = $3, since = $4, resolved_at = $5
			WHERE id = $1`, in.ID, in.BodyRegion, in.Description, in.Since, in.ResolvedAt); err != nil {
			return err
		}
		out = in
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.StudentInjury{}, ErrNotFound
	}
	if err != nil {
		return domain.StudentInjury{}, fmt.Errorf("repo: atualizar lesão: %w", err)
	}
	return out, nil
}

// Delete apaga uma lesão do aluno; ErrNotFound quando não existe para ele.
func (r *InjuryRepo) Delete(ctx context.Context, tenantID, studentID, id string) error {
	var affected int64
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM student_injuries WHERE id = $1 AND student_id = $2`, id, studentID)
		if err != nil {
			return err
		}
		affected = tag.RowsAffected()
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: apagar lesão: %w", err)
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}
