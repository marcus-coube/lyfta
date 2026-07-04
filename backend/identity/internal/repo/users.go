package repo

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// UserRepo dá acesso à tabela users e à user_roles associada. Toda operação
// passa por WithTenant para respeitar RLS (ADR-001): `app.tenant_id` é
// setado na transação antes de qualquer SELECT/INSERT.
type UserRepo struct {
	pool *pgxpool.Pool
}

// NewUserRepo cria um UserRepo sobre o pool informado.
func NewUserRepo(pool *pgxpool.Pool) *UserRepo {
	return &UserRepo{pool: pool}
}

// Create insere um usuário e seus papéis dentro do tenant informado,
// respeitando RLS via WithTenant.
func (r *UserRepo) Create(ctx context.Context, u domain.User) (domain.User, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.User{}, fmt.Errorf("repo: gerar id do usuário: %w", err)
	}
	u.ID = id.String()

	err = WithTenant(ctx, r.pool, u.TenantID, func(tx pgx.Tx) error {
		const qUser = `
			INSERT INTO users (id, tenant_id, email, password_hash, name, locale, status)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING created_at`
		if err := tx.QueryRow(ctx, qUser,
			u.ID, u.TenantID, u.Email, u.PasswordHash, u.Name, u.Locale, string(u.Status),
		).Scan(&u.CreatedAt); err != nil {
			return fmt.Errorf("repo: criar usuário: %w", err)
		}

		const qRole = `INSERT INTO user_roles (user_id, tenant_id, role) VALUES ($1, $2, $3)`
		for _, role := range u.Roles {
			if _, err := tx.Exec(ctx, qRole, u.ID, u.TenantID, string(role)); err != nil {
				return fmt.Errorf("repo: atribuir papel %q: %w", role, err)
			}
		}
		return nil
	})
	if err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// FindByEmailInTenant busca um usuário por e-mail dentro do tenant
// informado — RLS garante que não vaza para fora do tenant setado.
func (r *UserRepo) FindByEmailInTenant(ctx context.Context, tenantID, email string) (domain.User, error) {
	var u domain.User
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const qUser = `
			SELECT id, tenant_id, email, password_hash, name, locale, status, created_at
			FROM users WHERE email = $1`
		if err := tx.QueryRow(ctx, qUser, email).Scan(
			&u.ID, &u.TenantID, &u.Email, &u.PasswordHash, &u.Name, &u.Locale, &u.Status, &u.CreatedAt,
		); err != nil {
			if err == pgx.ErrNoRows {
				return ErrNotFound
			}
			return fmt.Errorf("repo: buscar usuário por e-mail: %w", err)
		}

		const qRoles = `SELECT role FROM user_roles WHERE user_id = $1`
		rows, err := tx.Query(ctx, qRoles, u.ID)
		if err != nil {
			return fmt.Errorf("repo: buscar papéis: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			var role string
			if err := rows.Scan(&role); err != nil {
				return fmt.Errorf("repo: ler papel: %w", err)
			}
			u.Roles = append(u.Roles, domain.Role(role))
		}
		return rows.Err()
	})
	if err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// ListByTenant lista todos os usuários visíveis sob o tenant_id setado —
// usado nos testes de isolamento de RLS.
func (r *UserRepo) ListByTenant(ctx context.Context, tenantID string) ([]domain.User, error) {
	var users []domain.User
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `SELECT id, tenant_id, email, name, locale, status, created_at FROM users ORDER BY created_at`
		rows, err := tx.Query(ctx, q)
		if err != nil {
			return fmt.Errorf("repo: listar usuários: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			var u domain.User
			if err := rows.Scan(&u.ID, &u.TenantID, &u.Email, &u.Name, &u.Locale, &u.Status, &u.CreatedAt); err != nil {
				return fmt.Errorf("repo: ler usuário: %w", err)
			}
			users = append(users, u)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return users, nil
}
