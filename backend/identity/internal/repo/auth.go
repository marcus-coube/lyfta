package repo

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// RefreshTokenTTL é a validade do refresh token (não especificada no plano —
// 30 dias é o padrão adotado; revisar se o produto pedir "lembrar de mim").
const RefreshTokenTTL = 30 * 24 * time.Hour

// AuthRepo dá acesso ao lookup de e-mail entre tenants e à rotação de
// refresh tokens.
type AuthRepo struct {
	pool *pgxpool.Pool
}

// NewAuthRepo cria um AuthRepo sobre o pool informado.
func NewAuthRepo(pool *pgxpool.Pool) *AuthRepo {
	return &AuthRepo{pool: pool}
}

// HashToken aplica SHA-256 a um token em claro para armazenamento (nunca
// gravamos o token em texto puro).
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// FindTenantsByEmail resolve em quais tenants existe uma conta ativa com o
// e-mail informado (ADR-002 §2b/2c: login precisa desambiguar antes de
// autenticar).
//
// Isso roda ANTES de sabermos qual app.tenant_id setar, então uma query
// comum contra `users` sob RLS forçada (ADR-001) não retorna nada — a
// policy tenant_isolation compara tenant_id a current_setting(...), que é
// NULL sem tenant setado. Por isso chamamos a função de banco
// find_tenants_by_email (migration 0008_email_lookup), SECURITY DEFINER,
// de superfície mínima: devolve só (user_id, tenant_id, tenant_name) para o
// e-mail exato, nunca password_hash ou qualquer outra coluna. Único ponto de
// exceção documentado ao modelo de RLS; todo o restante do acesso a dados
// continua via WithTenant.
func (r *AuthRepo) FindTenantsByEmail(ctx context.Context, email string) ([]domain.TenantMatch, error) {
	const q = `SELECT user_id, tenant_id, tenant_name FROM find_tenants_by_email($1)`
	rows, err := r.pool.Query(ctx, q, email)
	if err != nil {
		return nil, fmt.Errorf("repo: resolver e-mail entre tenants: %w", err)
	}
	defer rows.Close()

	var matches []domain.TenantMatch
	for rows.Next() {
		var m domain.TenantMatch
		if err := rows.Scan(&m.UserID, &m.TenantID, &m.TenantName); err != nil {
			return nil, fmt.Errorf("repo: ler match de tenant: %w", err)
		}
		matches = append(matches, m)
	}
	return matches, rows.Err()
}

// CreateRefreshToken insere um novo refresh token (já com o hash calculado)
// dentro do tenant do usuário, respeitando RLS via WithTenant.
func (r *AuthRepo) CreateRefreshToken(ctx context.Context, tenantID, userID, tokenHash string, expiresAt time.Time) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("repo: gerar id do refresh token: %w", err)
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO refresh_tokens (id, user_id, tenant_id, token_hash, expires_at)
			VALUES ($1, $2, $3, $4, $5)`
		_, err := tx.Exec(ctx, q, id.String(), userID, tenantID, tokenHash, expiresAt)
		return err
	})
	if err != nil {
		return "", fmt.Errorf("repo: criar refresh token: %w", err)
	}
	return id.String(), nil
}

// FindValidRefreshToken busca um refresh token válido (não revogado, não
// expirado) pelo hash, dentro do tenant informado.
func (r *AuthRepo) FindValidRefreshToken(ctx context.Context, tenantID, tokenHash string) (domain.RefreshToken, error) {
	var rt domain.RefreshToken
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT id, user_id, tenant_id, token_hash, expires_at, revoked_at, created_at
			FROM refresh_tokens
			WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`
		err := tx.QueryRow(ctx, q, tokenHash).Scan(
			&rt.ID, &rt.UserID, &rt.TenantID, &rt.TokenHash, &rt.ExpiresAt, &rt.RevokedAt, &rt.CreatedAt,
		)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		if err == ErrNotFound {
			return domain.RefreshToken{}, ErrNotFound
		}
		return domain.RefreshToken{}, fmt.Errorf("repo: buscar refresh token: %w", err)
	}
	return rt, nil
}

// RevokeRefreshToken marca um refresh token como revogado (usado tanto no
// logout quanto na rotação do refresh, que revoga o token antigo).
func (r *AuthRepo) RevokeRefreshToken(ctx context.Context, tenantID, id string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL`
		_, err := tx.Exec(ctx, q, id)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: revogar refresh token: %w", err)
	}
	return nil
}

// FindUserByID busca um usuário (com papéis) por id dentro do tenant —
// usado no refresh, que só tem o tenant_id do token, não o e-mail.
func (r *AuthRepo) FindUserByID(ctx context.Context, tenantID, userID string) (domain.User, error) {
	var u domain.User
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const qUser = `
			SELECT id, tenant_id, email, name, locale, status, created_at
			FROM users WHERE id = $1`
		if err := tx.QueryRow(ctx, qUser, userID).Scan(
			&u.ID, &u.TenantID, &u.Email, &u.Name, &u.Locale, &u.Status, &u.CreatedAt,
		); err != nil {
			if err == pgx.ErrNoRows {
				return ErrNotFound
			}
			return fmt.Errorf("repo: buscar usuário por id: %w", err)
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
		if err == ErrNotFound {
			return domain.User{}, ErrNotFound
		}
		return domain.User{}, err
	}
	return u, nil
}
