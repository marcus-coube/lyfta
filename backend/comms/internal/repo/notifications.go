package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NotificationLogRepo dá acesso ao registro de push enviado (P3.4) — auditoria
// ("chegou mesmo?") e dedupe do job diário. Toda operação passa por
// WithTenant (ADR-001 §2).
type NotificationLogRepo struct {
	pool *pgxpool.Pool
}

// NewNotificationLogRepo cria um NotificationLogRepo sobre o pool informado.
func NewNotificationLogRepo(pool *pgxpool.Pool) *NotificationLogRepo {
	return &NotificationLogRepo{pool: pool}
}

// Record grava um push efetivamente enviado — um registro por envio (não por
// usuário): um usuário com dois devices que recebe dois pushes gera duas
// linhas, e o dedupe (ExistsInRange) não se importa com isso, porque só
// pergunta "existe ALGUMA linha desse kind pra esse usuário no intervalo".
func (r *NotificationLogRepo) Record(ctx context.Context, tenantID, userID, kind string, payload map[string]any) error {
	id, err := uuid.NewV7()
	if err != nil {
		return fmt.Errorf("repo: gerar id do log de notificação: %w", err)
	}
	if payload == nil {
		payload = map[string]any{}
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO notification_log (id, tenant_id, user_id, kind, payload)
			VALUES ($1, $2, $3, $4, $5)`,
			id.String(), tenantID, userID, kind, payload)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: gravar log de notificação: %w", err)
	}
	return nil
}

// ExistsInRange responde "já mandei este `kind` pra este usuário no
// intervalo [since, until)?" — a pergunta de dedupe do job diário (P3.4).
// Filtra por faixa em vez de índice funcional sobre `sent_at::date` porque
// esse cast não é IMMUTABLE (depende do timezone da sessão, ver Notas de
// execução da P3.1) — a faixa usa o mesmo índice
// idx_notification_log_dedupe (tenant_id, user_id, kind, sent_at DESC).
func (r *NotificationLogRepo) ExistsInRange(ctx context.Context, tenantID, userID, kind string, since, until time.Time) (bool, error) {
	var exists bool
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM notification_log
				WHERE tenant_id = $1 AND user_id = $2 AND kind = $3
				  AND sent_at >= $4 AND sent_at < $5
			)`, tenantID, userID, kind, since, until).Scan(&exists)
	})
	if err != nil {
		return false, fmt.Errorf("repo: checar dedupe de notificação: %w", err)
	}
	return exists, nil
}
