package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErasureRepo cuida do que o financeiro faz quando o aluno exclui a conta
// (ADR-017 §5, P7.5).
type ErasureRepo struct{ pool *pgxpool.Pool }

// NewErasureRepo cria o repositório.
func NewErasureRepo(pool *pgxpool.Pool) *ErasureRepo { return &ErasureRepo{pool: pool} }

// Pending conta as faturas `open` e `overdue` do aluno. Qualquer uma delas
// bloqueia a exclusão da conta.
func (r *ErasureRepo) Pending(ctx context.Context, tenantID, studentID string) (open, overdue int, err error) {
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT count(*) FILTER (WHERE status = 'open'),
			       count(*) FILTER (WHERE status = 'overdue')
			FROM invoices WHERE student_id = $1`, studentID).Scan(&open, &overdue)
	})
	if err != nil {
		return 0, 0, fmt.Errorf("repo: faturas pendentes do aluno: %w", err)
	}
	return open, overdue, nil
}

// EraseStudent registra a exclusão da conta no financeiro, numa transação e
// de forma idempotente: cancela a assinatura vigente (ativa ou pausada) e as
// faturas `open` com vencimento depois de `today`, e marca o titular com
// `account_deleted_at`, guardando nome e e-mail recebidos. Faturas e
// pagamentos ficam intactos. Aluno sem registro financeiro não vira
// registro novo — nada a reter. Repetir a chamada não altera o que já foi
// gravado (nem o nome/e-mail da primeira exclusão).
func (r *ErasureRepo) EraseStudent(ctx context.Context, tenantID, studentID, name, email string, today time.Time) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE invoices SET status = 'canceled', updated_at = now()
			WHERE student_id = $1 AND status = 'open' AND due_date > $2::date`,
			studentID, today.Format(time.DateOnly)); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE subscriptions SET status = 'canceled', canceled_at = now(), updated_at = now()
			WHERE student_id = $1 AND status IN ('active', 'paused')`, studentID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			UPDATE billing_customers
			SET name = $2, email = $3, account_deleted_at = now(), updated_at = now()
			WHERE student_id = $1 AND account_deleted_at IS NULL`, studentID, name, email)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: excluir aluno do financeiro: %w", err)
	}
	return nil
}
