package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// WithTenant abre uma transação, seta `app.tenant_id` (usado pelas policies de
// RLS via current_setting, ADR-001 §2) e executa fn. Commit em caso de
// sucesso, rollback em caso de erro.
//
// O escopo é a transação, não a requisição: `set_config(..., true)` é
// SET LOCAL, e uma conexão só fica presa a um tenant enquanto a transação
// dura. Por isso o tenant entra aqui, no repositório, e não num middleware
// HTTP que precisaria segurar conexão do pool pela requisição inteira.
func WithTenant(ctx context.Context, pool *pgxpool.Pool, tenantID string, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("repo: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, "SELECT set_config('app.tenant_id', $1, true)", tenantID); err != nil {
		return fmt.Errorf("repo: set app.tenant_id: %w", err)
	}

	if err := fn(tx); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("repo: commit tx: %w", err)
	}
	return nil
}
