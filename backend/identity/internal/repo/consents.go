package repo

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// ConsentRepo dá acesso ao registro append-only de consentimentos (ADR-008
// §1, P4.5). Sempre dentro do tenant setado (RLS).
type ConsentRepo struct {
	pool *pgxpool.Pool
}

// NewConsentRepo cria um ConsentRepo sobre o pool informado.
func NewConsentRepo(pool *pgxpool.Pool) *ConsentRepo {
	return &ConsentRepo{pool: pool}
}

// grantConsentsTx concede as finalidades dentro de uma transação já com
// app.tenant_id setado. Idempotente: finalidade já vigente na mesma versão
// dos termos não gera linha nova; vigente numa versão antiga é encerrada
// (revoked_at) e substituída por uma linha na versão atual.
func grantConsentsTx(ctx context.Context, tx pgx.Tx, tenantID, userID, termsVersion string, purposes []string) error {
	for _, purpose := range purposes {
		var currentVersion string
		err := tx.QueryRow(ctx,
			`SELECT terms_version FROM consents WHERE user_id = $1 AND purpose = $2 AND revoked_at IS NULL`,
			userID, purpose).Scan(&currentVersion)
		switch {
		case err == nil && currentVersion == termsVersion:
			continue
		case err == nil:
			if _, err := tx.Exec(ctx,
				`UPDATE consents SET revoked_at = now() WHERE user_id = $1 AND purpose = $2 AND revoked_at IS NULL`,
				userID, purpose); err != nil {
				return fmt.Errorf("repo: encerrar consentimento antigo: %w", err)
			}
		case err != pgx.ErrNoRows:
			return fmt.Errorf("repo: ler consentimento vigente: %w", err)
		}

		id, err := uuid.NewV7()
		if err != nil {
			return fmt.Errorf("repo: gerar id do consentimento: %w", err)
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO consents (id, tenant_id, user_id, purpose, terms_version) VALUES ($1, $2, $3, $4, $5)`,
			id.String(), tenantID, userID, purpose, termsVersion); err != nil {
			return fmt.Errorf("repo: gravar consentimento: %w", err)
		}
	}
	return nil
}

// Apply aplica uma mudança de consentimentos numa transação: `true` concede
// (na versão informada), `false` revoga. Revogar nunca apaga a linha.
func (r *ConsentRepo) Apply(ctx context.Context, tenantID, userID, termsVersion string, changes map[string]bool) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var grant []string
		for purpose, on := range changes {
			if on {
				grant = append(grant, purpose)
				continue
			}
			if _, err := tx.Exec(ctx,
				`UPDATE consents SET revoked_at = now() WHERE user_id = $1 AND purpose = $2 AND revoked_at IS NULL`,
				userID, purpose); err != nil {
				return fmt.Errorf("repo: revogar consentimento: %w", err)
			}
		}
		return grantConsentsTx(ctx, tx, tenantID, userID, termsVersion, grant)
	})
	if err != nil {
		return fmt.Errorf("repo: aplicar consentimentos: %w", err)
	}
	return nil
}

// Active devolve as linhas vigentes (não revogadas) do usuário, de qualquer
// versão dos termos.
func (r *ConsentRepo) Active(ctx context.Context, tenantID, userID string) ([]domain.Consent, error) {
	var out []domain.Consent
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, tenant_id, user_id, purpose, terms_version, granted_at, revoked_at
			FROM consents WHERE user_id = $1 AND revoked_at IS NULL ORDER BY purpose`, userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var c domain.Consent
			if err := rows.Scan(&c.ID, &c.TenantID, &c.UserID, &c.Purpose, &c.TermsVersion, &c.GrantedAt, &c.RevokedAt); err != nil {
				return err
			}
			out = append(out, c)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar consentimentos: %w", err)
	}
	return out, nil
}

// ActivePurposes devolve só as finalidades vigentes na versão atual dos
// termos — é o que vai nas claims do JWT e no endpoint interno. Termo novo
// derruba todas: o usuário precisa consentir de novo.
func (r *ConsentRepo) ActivePurposes(ctx context.Context, tenantID, userID, termsVersion string) ([]string, error) {
	active, err := r.Active(ctx, tenantID, userID)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(active))
	for _, c := range active {
		if c.TermsVersion == termsVersion {
			out = append(out, c.Purpose)
		}
	}
	return out, nil
}
