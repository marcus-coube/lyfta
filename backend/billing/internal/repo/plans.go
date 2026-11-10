package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Plan é um plano de mensalidade (só o owner escreve, ADR-017 §3).
type Plan struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	AmountCents int64     `json:"amount_cents"`
	Currency    string    `json:"currency"`
	Active      bool      `json:"active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

const planColumns = `id, name, amount_cents, currency, active, created_at, updated_at`

func scanPlan(row pgx.Row) (Plan, error) {
	var p Plan
	err := row.Scan(&p.ID, &p.Name, &p.AmountCents, &p.Currency, &p.Active, &p.CreatedAt, &p.UpdatedAt)
	return p, err
}

// PlanRepo dá acesso a billing_plans.
type PlanRepo struct{ pool *pgxpool.Pool }

// NewPlanRepo cria o repositório de planos.
func NewPlanRepo(pool *pgxpool.Pool) *PlanRepo { return &PlanRepo{pool: pool} }

// List devolve os planos do tenant; onlyActive esconde os arquivados.
func (r *PlanRepo) List(ctx context.Context, tenantID string, onlyActive bool) ([]Plan, error) {
	items := []Plan{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+planColumns+` FROM billing_plans
			WHERE (NOT $1 OR active) ORDER BY active DESC, name, id`, onlyActive)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			p, err := scanPlan(rows)
			if err != nil {
				return err
			}
			items = append(items, p)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar planos: %w", err)
	}
	return items, nil
}

// Create grava um plano ativo.
func (r *PlanRepo) Create(ctx context.Context, tenantID, name string, amountCents int64) (Plan, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return Plan{}, fmt.Errorf("repo: gerar id do plano: %w", err)
	}
	var p Plan
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		p, err = scanPlan(tx.QueryRow(ctx, `INSERT INTO billing_plans (id, tenant_id, name, amount_cents)
			VALUES ($1, $2, $3, $4) RETURNING `+planColumns, id.String(), tenantID, name, amountCents))
		return err
	})
	if err != nil {
		return Plan{}, fmt.Errorf("repo: criar plano: %w", err)
	}
	return p, nil
}

// Update troca nome e valor. Assinaturas existentes mantêm o valor delas
// (cópia no momento de assinar).
func (r *PlanRepo) Update(ctx context.Context, tenantID, id, name string, amountCents int64) (Plan, error) {
	var p Plan
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		p, err = scanPlan(tx.QueryRow(ctx, `UPDATE billing_plans SET name = $2, amount_cents = $3, updated_at = now()
			WHERE id = $1 RETURNING `+planColumns, id, name, amountCents))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Plan{}, ErrNotFound
	}
	if err != nil {
		return Plan{}, fmt.Errorf("repo: atualizar plano: %w", err)
	}
	return p, nil
}

// Archive desativa o plano (idempotente); plano arquivado não aceita
// assinatura nova.
func (r *PlanRepo) Archive(ctx context.Context, tenantID, id string) (Plan, error) {
	var p Plan
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		p, err = scanPlan(tx.QueryRow(ctx, `UPDATE billing_plans SET active = false,
			updated_at = CASE WHEN active THEN now() ELSE updated_at END
			WHERE id = $1 RETURNING `+planColumns, id))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Plan{}, ErrNotFound
	}
	if err != nil {
		return Plan{}, fmt.Errorf("repo: arquivar plano: %w", err)
	}
	return p, nil
}
