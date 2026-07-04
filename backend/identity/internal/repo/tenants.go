package repo

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// TenantRepo dá acesso à tabela global tenants (sem RLS — ADR-001 §5).
type TenantRepo struct {
	pool *pgxpool.Pool
}

// NewTenantRepo cria um TenantRepo sobre o pool informado.
func NewTenantRepo(pool *pgxpool.Pool) *TenantRepo {
	return &TenantRepo{pool: pool}
}

// Create insere um novo tenant com id UUID v7 gerado pela aplicação.
func (r *TenantRepo) Create(ctx context.Context, t domain.Tenant) (domain.Tenant, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Tenant{}, fmt.Errorf("repo: gerar id do tenant: %w", err)
	}
	t.ID = id.String()

	const q = `
		INSERT INTO tenants (id, name, slug, locale)
		VALUES ($1, $2, $3, $4)
		RETURNING created_at`
	if err := r.pool.QueryRow(ctx, q, t.ID, t.Name, t.Slug, t.Locale).Scan(&t.CreatedAt); err != nil {
		return domain.Tenant{}, fmt.Errorf("repo: criar tenant: %w", err)
	}
	return t, nil
}

// FindByID busca um tenant por id.
func (r *TenantRepo) FindByID(ctx context.Context, id string) (domain.Tenant, error) {
	const q = `SELECT id, name, slug, locale, created_at FROM tenants WHERE id = $1`
	var t domain.Tenant
	err := r.pool.QueryRow(ctx, q, id).Scan(&t.ID, &t.Name, &t.Slug, &t.Locale, &t.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Tenant{}, ErrNotFound
		}
		return domain.Tenant{}, fmt.Errorf("repo: buscar tenant: %w", err)
	}
	return t, nil
}
