package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// PasswordResetTTL é a validade do token de recuperação de senha (plano
// P0.4: 1 hora).
const PasswordResetTTL = 1 * time.Hour

// PasswordResetRepo dá acesso à tabela password_resets, sempre dentro do
// tenant setado (RLS, ADR-001).
type PasswordResetRepo struct {
	pool *pgxpool.Pool
}

// NewPasswordResetRepo cria um PasswordResetRepo sobre o pool informado.
func NewPasswordResetRepo(pool *pgxpool.Pool) *PasswordResetRepo {
	return &PasswordResetRepo{pool: pool}
}

// Create insere um novo pedido de recuperação de senha com o hash do token
// já calculado.
func (r *PasswordResetRepo) Create(ctx context.Context, pr domain.PasswordReset) (domain.PasswordReset, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.PasswordReset{}, fmt.Errorf("repo: gerar id do reset: %w", err)
	}
	pr.ID = id.String()

	err = WithTenant(ctx, r.pool, pr.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO password_resets (id, user_id, tenant_id, token_hash, expires_at)
			VALUES ($1, $2, $3, $4, $5)
			RETURNING created_at`
		return tx.QueryRow(ctx, q, pr.ID, pr.UserID, pr.TenantID, pr.TokenHash, pr.ExpiresAt).Scan(&pr.CreatedAt)
	})
	if err != nil {
		return domain.PasswordReset{}, fmt.Errorf("repo: criar pedido de reset: %w", err)
	}
	return pr, nil
}

// FindValidByTokenHash busca um pedido de reset válido (não expirado, não
// usado) pelo hash do token. Endpoint público (reset-password ainda não sabe
// o tenant_id), então usa a mesma estratégia de função SECURITY DEFINER
// (migration 0009: find_password_reset_by_token), de superfície mínima.
func (r *PasswordResetRepo) FindValidByTokenHash(ctx context.Context, tokenHash string) (domain.PasswordReset, error) {
	const q = `
		SELECT id, user_id, tenant_id, token_hash, expires_at, used_at, created_at
		FROM find_password_reset_by_token($1)`
	var pr domain.PasswordReset
	err := r.pool.QueryRow(ctx, q, tokenHash).Scan(
		&pr.ID, &pr.UserID, &pr.TenantID, &pr.TokenHash, &pr.ExpiresAt, &pr.UsedAt, &pr.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.PasswordReset{}, ErrNotFound
		}
		return domain.PasswordReset{}, fmt.Errorf("repo: buscar reset por token: %w", err)
	}
	return pr, nil
}

// MarkUsed marca um pedido de reset como usado (uso único).
func (r *PasswordResetRepo) MarkUsed(ctx context.Context, tenantID, id string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE password_resets SET used_at = now() WHERE id = $1 AND used_at IS NULL`
		_, err := tx.Exec(ctx, q, id)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: marcar reset usado: %w", err)
	}
	return nil
}
