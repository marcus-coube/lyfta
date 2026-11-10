package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// JobRepo reúne as operações do job mensal (P7.3). Cada método trabalha em um
// tenant por transação (RLS) e é idempotente: rodar de novo no mesmo dia não
// duplica nem altera nada.
type JobRepo struct{ pool *pgxpool.Pool }

// NewJobRepo cria o repositório do job.
func NewJobRepo(pool *pgxpool.Pool) *JobRepo { return &JobRepo{pool: pool} }

// GenerateInvoices garante a fatura do mês corrente (today = data civil no
// fuso do tenant, 00:00 UTC) para cada assinatura `active`. O vencimento é o
// de DueDateFor (mesma regra da criação da assinatura); assinatura cujo
// `starts_on` é de mês futuro não gera, e a pausada/cancelada também não.
// `ON CONFLICT DO NOTHING` no unique (subscription_id, period) torna o job
// idempotente — inclusive contra a fatura criada junto da assinatura. Devolve
// quantas faturas nasceram.
func (r *JobRepo) GenerateInvoices(ctx context.Context, tenantID string, today time.Time) (int, error) {
	period := today.Format("2006-01")
	created := 0
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, student_id, amount_cents, due_day, starts_on::text
			FROM subscriptions
			WHERE status = 'active' AND to_char(starts_on, 'YYYY-MM') <= $1
			ORDER BY created_at, id`, period)
		if err != nil {
			return err
		}
		type sub struct {
			id, studentID string
			amount        int64
			dueDay        int
			startsOn      time.Time
		}
		var subs []sub
		for rows.Next() {
			var s sub
			var starts string
			if err := rows.Scan(&s.id, &s.studentID, &s.amount, &s.dueDay, &starts); err != nil {
				rows.Close()
				return err
			}
			if s.startsOn, err = time.Parse(time.DateOnly, starts); err != nil {
				rows.Close()
				return err
			}
			subs = append(subs, s)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		for _, s := range subs {
			id, err := uuid.NewV7()
			if err != nil {
				return fmt.Errorf("repo: gerar id da fatura: %w", err)
			}
			due := DueDateFor(today, s.dueDay, s.startsOn)
			tag, err := tx.Exec(ctx, `
				INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents)
				VALUES ($1, $2, $3, $4, $5, $6::date, $7)
				ON CONFLICT (tenant_id, subscription_id, period) DO NOTHING`,
				id.String(), tenantID, s.id, s.studentID, period, due.Format(time.DateOnly), s.amount)
			if err != nil {
				return err
			}
			created += int(tag.RowsAffected())
		}
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("repo: gerar faturas do mês: %w", err)
	}
	return created, nil
}

// MarkOverdue vira `overdue` toda fatura `open` com vencimento anterior a
// today (data civil no fuso do tenant). Devolve quantas mudaram.
func (r *JobRepo) MarkOverdue(ctx context.Context, tenantID string, today time.Time) (int, error) {
	n := 0
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE invoices SET status = 'overdue', updated_at = now()
			WHERE status = 'open' AND due_date < $1::date`, today.Format(time.DateOnly))
		n = int(tag.RowsAffected())
		return err
	})
	if err != nil {
		return 0, fmt.Errorf("repo: vencer faturas: %w", err)
	}
	return n, nil
}
