package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// MonthTotal é o recebido de um mês (AAAA-MM).
type MonthTotal struct {
	Period        string
	ReceivedCents int64
}

// Summary é o resumo financeiro do dashboard do owner (P8.1).
type Summary struct {
	Period            string
	ReceivedCents     int64
	ToReceiveCents    int64
	ToReceiveCount    int
	OverdueCents      int64
	OverdueCount      int
	DelinquentStudent int
	Series            []MonthTotal
}

// SeriesMonths é o tamanho da série de recebido (meses terminando em `period`).
const SeriesMonths = 6

// Summary calcula, no tenant:
//   - recebido: faturas `paid` cujo `paid_at` cai no mês, no fuso `tz`;
//   - a receber: faturas `open` com vencimento no mês;
//   - vencido: faturas `overdue` de qualquer mês (estoque atual), em valor e
//     quantidade, e quantos alunos distintos têm alguma;
//   - série: recebido dos SeriesMonths meses que terminam em `period`.
//
// `period` é AAAA-MM; `tz` é o nome IANA do fuso do tenant.
func (r *InvoiceRepo) Summary(ctx context.Context, tenantID, period, tz string, monthStart time.Time) (Summary, error) {
	s := Summary{Period: period}
	months := make([]string, SeriesMonths)
	for i := 0; i < SeriesMonths; i++ {
		months[i] = monthStart.AddDate(0, -(SeriesMonths - 1 - i), 0).Format("2006-01")
	}
	totals := map[string]int64{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			SELECT
			  COALESCE(SUM(amount_cents) FILTER (WHERE status = 'open' AND to_char(due_date, 'YYYY-MM') = $1), 0),
			  COUNT(*) FILTER (WHERE status = 'open' AND to_char(due_date, 'YYYY-MM') = $1),
			  COALESCE(SUM(amount_cents) FILTER (WHERE status = 'overdue'), 0),
			  COUNT(*) FILTER (WHERE status = 'overdue'),
			  COUNT(DISTINCT student_id) FILTER (WHERE status = 'overdue')
			FROM invoices`, period).Scan(&s.ToReceiveCents, &s.ToReceiveCount, &s.OverdueCents, &s.OverdueCount, &s.DelinquentStudent); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `
			SELECT to_char(paid_at AT TIME ZONE $2, 'YYYY-MM') AS p, SUM(amount_cents)
			FROM invoices
			WHERE status = 'paid' AND to_char(paid_at AT TIME ZONE $2, 'YYYY-MM') = ANY($1::text[])
			GROUP BY p`, months, tz)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var p string
			var sum int64
			if err := rows.Scan(&p, &sum); err != nil {
				return err
			}
			totals[p] = sum
		}
		return rows.Err()
	})
	if err != nil {
		return Summary{}, fmt.Errorf("repo: resumo financeiro: %w", err)
	}
	for _, m := range months {
		s.Series = append(s.Series, MonthTotal{Period: m, ReceivedCents: totals[m]})
	}
	s.ReceivedCents = totals[period]
	return s, nil
}
