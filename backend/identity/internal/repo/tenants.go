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

// CreateWithOwner cria o tenant e o usuário owner (com seus papéis) na mesma
// transação (plano P0.3: signup cria tenant + user owner "numa transação").
// `tenants` não tem RLS (tabela global, ADR-001 §5) e pode ser inserida
// direto na tx; `users`/`user_roles` têm RLS, então setamos
// `app.tenant_id` (SELECT set_config, igual a WithTenant) antes de inseri-las,
// dentro da mesma transação — se qualquer passo falhar, tudo é revertido
// (nunca fica tenant órfão sem usuário).
func (r *TenantRepo) CreateWithOwner(ctx context.Context, t domain.Tenant, u domain.User) (domain.Tenant, domain.User, error) {
	tenantID, err := uuid.NewV7()
	if err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: gerar id do tenant: %w", err)
	}
	t.ID = tenantID.String()

	userID, err := uuid.NewV7()
	if err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: gerar id do usuário: %w", err)
	}
	u.ID = userID.String()
	u.TenantID = t.ID

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	const qTenant = `
		INSERT INTO tenants (id, name, slug, locale)
		VALUES ($1, $2, $3, $4)
		RETURNING created_at`
	if err := tx.QueryRow(ctx, qTenant, t.ID, t.Name, t.Slug, t.Locale).Scan(&t.CreatedAt); err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: criar tenant: %w", err)
	}

	if _, err := tx.Exec(ctx, "SELECT set_config('app.tenant_id', $1, true)", t.ID); err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: set app.tenant_id: %w", err)
	}

	const qUser = `
		INSERT INTO users (id, tenant_id, email, password_hash, name, locale, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING created_at`
	if err := tx.QueryRow(ctx, qUser,
		u.ID, u.TenantID, u.Email, u.PasswordHash, u.Name, u.Locale, string(u.Status),
	).Scan(&u.CreatedAt); err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: criar usuário owner: %w", err)
	}

	const qRole = `INSERT INTO user_roles (user_id, tenant_id, role) VALUES ($1, $2, $3)`
	for _, role := range u.Roles {
		if _, err := tx.Exec(ctx, qRole, u.ID, u.TenantID, string(role)); err != nil {
			return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: atribuir papel %q: %w", role, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: commit tx: %w", err)
	}
	return t, u, nil
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

// FindBySlug busca um tenant por slug — usado no signup para devolver
// 409 code:slug_taken sem depender só da constraint UNIQUE do banco.
func (r *TenantRepo) FindBySlug(ctx context.Context, slug string) (domain.Tenant, error) {
	const q = `SELECT id, name, slug, locale, created_at FROM tenants WHERE slug = $1`
	var t domain.Tenant
	err := r.pool.QueryRow(ctx, q, slug).Scan(&t.ID, &t.Name, &t.Slug, &t.Locale, &t.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Tenant{}, ErrNotFound
		}
		return domain.Tenant{}, fmt.Errorf("repo: buscar tenant por slug: %w", err)
	}
	return t, nil
}
