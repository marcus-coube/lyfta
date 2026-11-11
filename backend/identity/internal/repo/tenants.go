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
		RETURNING created_at, timezone, coach_billing_access`
	if err := r.pool.QueryRow(ctx, q, t.ID, t.Name, t.Slug, t.Locale).Scan(&t.CreatedAt, &t.Timezone, &t.CoachBillingAccess); err != nil {
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
func (r *TenantRepo) CreateWithOwner(ctx context.Context, t domain.Tenant, u domain.User, termsVersion string, consents []string) (domain.Tenant, domain.User, error) {
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
		RETURNING created_at, timezone, coach_billing_access`
	if err := tx.QueryRow(ctx, qTenant, t.ID, t.Name, t.Slug, t.Locale).Scan(&t.CreatedAt, &t.Timezone, &t.CoachBillingAccess); err != nil {
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

	// O aceite dos termos entra na mesma transação: tenant sem registro de
	// consentimento nunca existe (ADR-008 §6, P4.5).
	if err := grantConsentsTx(ctx, tx, u.TenantID, u.ID, termsVersion, consents); err != nil {
		return domain.Tenant{}, domain.User{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.Tenant{}, domain.User{}, fmt.Errorf("repo: commit tx: %w", err)
	}
	return t, u, nil
}

// FindByID busca um tenant por id.
func (r *TenantRepo) FindByID(ctx context.Context, id string) (domain.Tenant, error) {
	const q = `SELECT id, name, slug, locale, created_at, timezone, coach_billing_access FROM tenants WHERE id = $1`
	var t domain.Tenant
	err := r.pool.QueryRow(ctx, q, id).Scan(&t.ID, &t.Name, &t.Slug, &t.Locale, &t.CreatedAt, &t.Timezone, &t.CoachBillingAccess)
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
	const q = `SELECT id, name, slug, locale, created_at, timezone, coach_billing_access FROM tenants WHERE slug = $1`
	var t domain.Tenant
	err := r.pool.QueryRow(ctx, q, slug).Scan(&t.ID, &t.Name, &t.Slug, &t.Locale, &t.CreatedAt, &t.Timezone, &t.CoachBillingAccess)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Tenant{}, ErrNotFound
		}
		return domain.Tenant{}, fmt.Errorf("repo: buscar tenant por slug: %w", err)
	}
	return t, nil
}

// Update grava nome, fuso e acesso do coach ao financeiro (PUT /v1/tenant,
// P5.1). Slug e locale não mudam aqui.
func (r *TenantRepo) Update(ctx context.Context, t domain.Tenant) (domain.Tenant, error) {
	const q = `
		UPDATE tenants SET name = $2, timezone = $3, coach_billing_access = $4
		WHERE id = $1
		RETURNING id, name, slug, locale, created_at, timezone, coach_billing_access`
	var out domain.Tenant
	err := r.pool.QueryRow(ctx, q, t.ID, t.Name, t.Timezone, t.CoachBillingAccess).
		Scan(&out.ID, &out.Name, &out.Slug, &out.Locale, &out.CreatedAt, &out.Timezone, &out.CoachBillingAccess)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Tenant{}, ErrNotFound
		}
		return domain.Tenant{}, fmt.Errorf("repo: atualizar tenant: %w", err)
	}
	return out, nil
}

// MaxTenantPageSize é o teto do limit da varredura M2M de tenants.
const MaxTenantPageSize = 500

// ListAfter devolve até limit tenants com id > after, em ordem de id (cursor
// keyset), para os jobs que varrem todos os tenants (M2M, P5.1). after vazio
// começa do início. O handler pede limit+1 para saber se há próxima página, então
// o teto aqui é MaxTenantPageSize+1 (com o teto igual ao do handler, a linha
// extra era cortada e a página cheia nunca devolvia cursor: tenants além dos
// primeiros 500 ficavam fora dos jobs do billing e do comms).
func (r *TenantRepo) ListAfter(ctx context.Context, after string, limit int) ([]domain.Tenant, error) {
	if limit <= 0 || limit > MaxTenantPageSize+1 {
		limit = MaxTenantPageSize + 1
	}
	const q = `
		SELECT id, name, slug, locale, created_at, timezone, coach_billing_access
		FROM tenants
		WHERE ($1::text = '' OR id::text > $1::text)
		ORDER BY id
		LIMIT $2`
	rows, err := r.pool.Query(ctx, q, after, limit)
	if err != nil {
		return nil, fmt.Errorf("repo: listar tenants: %w", err)
	}
	defer rows.Close()
	var out []domain.Tenant
	for rows.Next() {
		var t domain.Tenant
		if err := rows.Scan(&t.ID, &t.Name, &t.Slug, &t.Locale, &t.CreatedAt, &t.Timezone, &t.CoachBillingAccess); err != nil {
			return nil, fmt.Errorf("repo: ler tenant: %w", err)
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("repo: listar tenants: %w", err)
	}
	return out, nil
}
