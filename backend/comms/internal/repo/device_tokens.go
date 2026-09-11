package repo

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
)

// DeviceTokenRepo dá acesso aos tokens de push (P3.4). Toda operação passa
// por WithTenant (ADR-001 §2).
type DeviceTokenRepo struct {
	pool *pgxpool.Pool
}

// NewDeviceTokenRepo cria um DeviceTokenRepo sobre o pool informado.
func NewDeviceTokenRepo(pool *pgxpool.Pool) *DeviceTokenRepo {
	return &DeviceTokenRepo{pool: pool}
}

const deviceTokenCols = `id, user_id, platform, token, locale, updated_at`

func scanDeviceToken(row pgx.Row, d *domain.DeviceToken) error {
	return row.Scan(&d.ID, &d.UserID, &d.Platform, &d.Token, &d.Locale, &d.UpdatedAt)
}

// Upsert grava (ou atualiza) o token do device por tenant+user+platform —
// unique da migration 0004. Reinstalar o app ou trocar de conta emite token
// novo; o locale também é reescrito a cada registro (o app manda o locale
// corrente, que pode ter mudado desde o último registro).
func (r *DeviceTokenRepo) Upsert(ctx context.Context, tenantID, userID string, platform domain.DevicePlatform, token, locale string) (domain.DeviceToken, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.DeviceToken{}, fmt.Errorf("repo: gerar id do device token: %w", err)
	}

	var d domain.DeviceToken
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `
			INSERT INTO device_tokens (id, tenant_id, user_id, platform, token, locale)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (tenant_id, user_id, platform) DO UPDATE
			SET token = EXCLUDED.token, locale = EXCLUDED.locale, updated_at = now()
			RETURNING ` + deviceTokenCols
		return scanDeviceToken(tx.QueryRow(ctx, q, id.String(), tenantID, userID, string(platform), token, locale), &d)
	})
	if err != nil {
		return domain.DeviceToken{}, fmt.Errorf("repo: registrar device token: %w", err)
	}
	d.TenantID = tenantID
	return d, nil
}

// ListForUser devolve os devices registrados de um usuário — a P3.4 manda
// push pra todos eles (um usuário pode ter o app aberto em mais de uma
// plataforma).
func (r *DeviceTokenRepo) ListForUser(ctx context.Context, tenantID, userID string) ([]domain.DeviceToken, error) {
	var out []domain.DeviceToken
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+deviceTokenCols+` FROM device_tokens WHERE user_id = $1`, userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var d domain.DeviceToken
			if err := scanDeviceToken(rows, &d); err != nil {
				return err
			}
			d.TenantID = tenantID
			out = append(out, d)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar device tokens: %w", err)
	}
	return out, nil
}

// Delete remove um token específico — chamado quando o FCM responde que o
// token não existe mais (app desinstalado, token trocado do lado do Google):
// sem isso o job diário tentaria mandar push pro mesmo token morto todo dia.
func (r *DeviceTokenRepo) Delete(ctx context.Context, tenantID, userID, token string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `DELETE FROM device_tokens WHERE user_id = $1 AND token = $2`, userID, token)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: apagar device token: %w", err)
	}
	return nil
}
