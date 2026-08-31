package repo

import (
	"context"
	"fmt"
	"strings"

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

// ActivateWithPassword define a senha (já com hash) de um usuário convidado e
// o ativa (status=active) — usado no accept de convite (P0.4).
func (r *UserRepo) ActivateWithPassword(ctx context.Context, tenantID, userID, passwordHash string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE users SET password_hash = $1, status = $2
			WHERE id = $3`
		_, err := tx.Exec(ctx, q, passwordHash, string(domain.UserStatusActive), userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: ativar usuário com senha: %w", err)
	}
	return nil
}

// UpdatePassword troca o hash de senha de um usuário (usado no reset).
func (r *UserRepo) UpdatePassword(ctx context.Context, tenantID, userID, passwordHash string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE users SET password_hash = $1 WHERE id = $2`
		_, err := tx.Exec(ctx, q, passwordHash, userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: atualizar senha: %w", err)
	}
	return nil
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

// UserFilter são os filtros da listagem de usuários do tenant (P1.6): a tela
// de alunos do professor. Campos vazios não filtram.
type UserFilter struct {
	Role   domain.Role
	Query  string
	Status domain.UserStatus
	// Cursor keyset: o nome e o id da última linha da página anterior.
	CursorName string
	CursorID   string
	Limit      int
}

// Tamanhos de página da listagem de usuários.
const (
	DefaultUserPageSize = 50
	MaxUserPageSize     = 200
)

// List devolve a página de usuários do tenant, ordenada por nome. hasMore diz
// se existe página seguinte — a query pede uma linha a mais e a descarta.
//
// A busca cobre nome e e-mail, sem distinguir caixa; o cursor é keyset sobre
// (nome, id), estável quando entra aluno novo no meio da lista.
func (r *UserRepo) List(ctx context.Context, tenantID string, f UserFilter) (users []domain.User, hasMore bool, err error) {
	limit := f.Limit
	if limit <= 0 {
		limit = DefaultUserPageSize
	}
	if limit > MaxUserPageSize {
		limit = MaxUserPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		// O papel filtra por EXISTS em user_roles: um usuário pode acumular
		// papéis (ADR-002), então um JOIN duplicaria linhas.
		const q = `
			SELECT u.id, u.tenant_id, u.email, u.name, u.locale, u.status, u.created_at,
			       COALESCE(
			           (SELECT array_agg(ur.role ORDER BY ur.role)
			            FROM user_roles ur WHERE ur.user_id = u.id),
			           '{}'
			       ) AS roles
			FROM users u
			WHERE ($1::text IS NULL OR EXISTS (
			          SELECT 1 FROM user_roles ur WHERE ur.user_id = u.id AND ur.role = $1))
			  AND ($2::text IS NULL OR u.status = $2)
			  AND ($3::text IS NULL OR u.name ILIKE $3 OR u.email ILIKE $3)
			  AND ($4::text IS NULL OR (u.name, u.id::text) > ($4, $5))
			ORDER BY u.name, u.id
			LIMIT $6`
		rows, queryErr := tx.Query(ctx, q,
			nullString(string(f.Role)), nullString(string(f.Status)),
			nullString(likePattern(f.Query)), nullString(f.CursorName), f.CursorID, limit+1)
		if queryErr != nil {
			return fmt.Errorf("repo: listar usuários: %w", queryErr)
		}
		defer rows.Close()
		for rows.Next() {
			var (
				u     domain.User
				roles []string
			)
			if scanErr := rows.Scan(&u.ID, &u.TenantID, &u.Email, &u.Name, &u.Locale,
				&u.Status, &u.CreatedAt, &roles); scanErr != nil {
				return fmt.Errorf("repo: ler usuário: %w", scanErr)
			}
			for _, role := range roles {
				u.Roles = append(u.Roles, domain.Role(role))
			}
			users = append(users, u)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, err
	}
	if len(users) > limit {
		return users[:limit], true, nil
	}
	return users, false, nil
}

// nullString manda NULL em vez de string vazia — é o que deixa os filtros
// opcionais dentro de uma query só.
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

// likePattern monta o padrão de busca escapando os curingas do LIKE, para que
// um nome com `%` não vire busca aberta.
func likePattern(query string) string {
	if query == "" {
		return ""
	}
	escaped := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(query)
	return "%" + escaped + "%"
}
