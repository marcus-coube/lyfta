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

// InvitationTTL é a validade do token de convite (plano P0.4: 7 dias).
const InvitationTTL = 7 * 24 * time.Hour

// InvitationRepo dá acesso à tabela invitations, sempre dentro do tenant
// setado (RLS, ADR-001).
type InvitationRepo struct {
	pool *pgxpool.Pool
}

// NewInvitationRepo cria um InvitationRepo sobre o pool informado.
func NewInvitationRepo(pool *pgxpool.Pool) *InvitationRepo {
	return &InvitationRepo{pool: pool}
}

// Create insere um novo convite com o hash do token já calculado.
func (r *InvitationRepo) Create(ctx context.Context, inv domain.Invitation) (domain.Invitation, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Invitation{}, fmt.Errorf("repo: gerar id do convite: %w", err)
	}
	inv.ID = id.String()

	err = WithTenant(ctx, r.pool, inv.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO invitations (id, tenant_id, email, role, token_hash, invited_by, expires_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING created_at`
		return tx.QueryRow(ctx, q,
			inv.ID, inv.TenantID, inv.Email, string(inv.Role), inv.TokenHash, inv.InvitedBy, inv.ExpiresAt,
		).Scan(&inv.CreatedAt)
	})
	if err != nil {
		return domain.Invitation{}, fmt.Errorf("repo: criar convite: %w", err)
	}
	return inv, nil
}

// FindByID busca um convite por id dentro do tenant informado.
func (r *InvitationRepo) FindByID(ctx context.Context, tenantID, id string) (domain.Invitation, error) {
	var inv domain.Invitation
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT id, tenant_id, email, role, token_hash, invited_by, expires_at, accepted_at, created_at
			FROM invitations WHERE id = $1`
		err := tx.QueryRow(ctx, q, id).Scan(
			&inv.ID, &inv.TenantID, &inv.Email, &inv.Role, &inv.TokenHash, &inv.InvitedBy,
			&inv.ExpiresAt, &inv.AcceptedAt, &inv.CreatedAt,
		)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		if err == ErrNotFound {
			return domain.Invitation{}, ErrNotFound
		}
		return domain.Invitation{}, fmt.Errorf("repo: buscar convite: %w", err)
	}
	return inv, nil
}

// FindValidByTokenHash busca um convite válido (não expirado, não aceito)
// pelo hash do token — usado no accept, que é público e ainda não sabe o
// tenant_id, então a busca roda como lyfta_app sem app.tenant_id setado.
// invitations não tem policy que permita isso sob RLS comum; por isso usamos
// a mesma estratégia de find_tenants_by_email: uma função SECURITY DEFINER
// (migration 0009), de superfície mínima (só pelo hash exato do token).
func (r *InvitationRepo) FindValidByTokenHash(ctx context.Context, tokenHash string) (domain.Invitation, error) {
	const q = `
		SELECT id, tenant_id, email, role, token_hash, invited_by, expires_at, accepted_at, created_at
		FROM find_invitation_by_token($1)`
	var inv domain.Invitation
	err := r.pool.QueryRow(ctx, q, tokenHash).Scan(
		&inv.ID, &inv.TenantID, &inv.Email, &inv.Role, &inv.TokenHash, &inv.InvitedBy,
		&inv.ExpiresAt, &inv.AcceptedAt, &inv.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Invitation{}, ErrNotFound
		}
		return domain.Invitation{}, fmt.Errorf("repo: buscar convite por token: %w", err)
	}
	return inv, nil
}

// MarkAccepted marca um convite como aceito (accepted_at), uso único.
func (r *InvitationRepo) MarkAccepted(ctx context.Context, tenantID, id string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE invitations SET accepted_at = now() WHERE id = $1 AND accepted_at IS NULL`
		_, err := tx.Exec(ctx, q, id)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: marcar convite aceito: %w", err)
	}
	return nil
}

// Invalidate marca um convite como expirado imediatamente — usado no
// reenvio, para que o token antigo pare de funcionar (plano P0.4: "invalida
// token anterior").
func (r *InvitationRepo) Invalidate(ctx context.Context, tenantID, id string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE invitations SET expires_at = now() WHERE id = $1 AND accepted_at IS NULL`
		_, err := tx.Exec(ctx, q, id)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: invalidar convite: %w", err)
	}
	return nil
}
