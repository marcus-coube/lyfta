package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Invoice é a fatura de um período (ADR-007 §2): imutável depois de paga —
// só o estorno a reabre (trigger da migration 0002).
type Invoice struct {
	ID             string     `json:"id"`
	SubscriptionID string     `json:"subscription_id"`
	StudentID      string     `json:"student_id"`
	Period         string     `json:"period"`
	DueDate        string     `json:"due_date"`
	AmountCents    int64      `json:"amount_cents"`
	Currency       string     `json:"currency"`
	Status         string     `json:"status"`
	PaidAt         *time.Time `json:"paid_at"`
	CreatedAt      time.Time  `json:"created_at"`
	Customer       Customer   `json:"customer"`
	Payments       []Payment  `json:"payments,omitempty"`
}

// Payment é um recebimento ou um estorno (append-only, ADR-007 §5).
type Payment struct {
	ID          string    `json:"id"`
	InvoiceID   string    `json:"invoice_id"`
	AmountCents int64     `json:"amount_cents"`
	Currency    string    `json:"currency"`
	Method      string    `json:"method"`
	PaidAt      time.Time `json:"paid_at"`
	RecordedBy  string    `json:"recorded_by"`
	Note        *string   `json:"note"`
	ReversedBy  *string   `json:"reversed_by"`
	ReversalOf  *string   `json:"reversal_of"`
	CreatedAt   time.Time `json:"created_at"`
}

const invoiceSelect = `
	SELECT i.id, i.subscription_id, i.student_id, i.period, i.due_date::text, i.amount_cents,
	       i.currency, i.status, i.paid_at, i.created_at,
	       COALESCE(c.name, ''), COALESCE(c.email, ''), COALESCE(c.account_deleted_at IS NOT NULL, false)
	FROM invoices i
	LEFT JOIN billing_customers c ON c.tenant_id = i.tenant_id AND c.student_id = i.student_id`

func scanInvoice(row pgx.Row) (Invoice, error) {
	var i Invoice
	err := row.Scan(&i.ID, &i.SubscriptionID, &i.StudentID, &i.Period, &i.DueDate, &i.AmountCents,
		&i.Currency, &i.Status, &i.PaidAt, &i.CreatedAt,
		&i.Customer.Name, &i.Customer.Email, &i.Customer.AccountDeleted)
	return i, err
}

const paymentColumns = `id, invoice_id, amount_cents, currency, method, paid_at, recorded_by, note,
	reversed_by, reversal_of, created_at`

func scanPayment(row pgx.Row) (Payment, error) {
	var p Payment
	err := row.Scan(&p.ID, &p.InvoiceID, &p.AmountCents, &p.Currency, &p.Method, &p.PaidAt,
		&p.RecordedBy, &p.Note, &p.ReversedBy, &p.ReversalOf, &p.CreatedAt)
	return p, err
}

// insertInvoice grava uma fatura nova (usado na criação da assinatura e,
// na P7.3, pelo job mensal).
func insertInvoice(ctx context.Context, tx pgx.Tx, tenantID, subID, studentID, period string, due time.Time, amount int64, status string) (Invoice, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return Invoice{}, fmt.Errorf("repo: gerar id da fatura: %w", err)
	}
	return scanInvoice(tx.QueryRow(ctx, `
		WITH ins AS (
			INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents, status)
			VALUES ($1, $2, $3, $4, $5, $6::date, $7, $8)
			RETURNING *
		)
		SELECT i.id, i.subscription_id, i.student_id, i.period, i.due_date::text, i.amount_cents,
		       i.currency, i.status, i.paid_at, i.created_at, '', '', false
		FROM ins i`,
		id.String(), tenantID, subID, studentID, period, due.Format(time.DateOnly), amount, status))
}

// InvoiceRepo dá acesso a invoices e payments.
type InvoiceRepo struct{ pool *pgxpool.Pool }

// NewInvoiceRepo cria o repositório de faturas e pagamentos.
func NewInvoiceRepo(pool *pgxpool.Pool) *InvoiceRepo { return &InvoiceRepo{pool: pool} }

// MaxInvoicePage é o teto de itens por página.
const MaxInvoicePage = 100

// InvoiceFilter são os filtros da listagem. StudentIDs limita o conjunto
// (nil = todos; vazio = nenhum, o coach sem alunos).
type InvoiceFilter struct {
	Status     string
	Period     string
	StudentID  string
	StudentIDs []string
	CursorDate string // YYYY-MM-DD do último item da página anterior
	CursorID   string
	Limit      int
}

// List devolve as faturas por vencimento decrescente (keyset), sem os
// pagamentos.
func (r *InvoiceRepo) List(ctx context.Context, tenantID string, f InvoiceFilter) (items []Invoice, hasMore bool, err error) {
	if f.Limit <= 0 || f.Limit > MaxInvoicePage {
		f.Limit = MaxInvoicePage
	}
	items = []Invoice{}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, invoiceSelect+`
			WHERE ($1::uuid[] IS NULL OR i.student_id = ANY($1))
			  AND ($2 = '' OR i.student_id = $2::uuid)
			  AND ($3 = '' OR i.status = $3)
			  AND ($4 = '' OR i.period = $4)
			  AND ($5 = '' OR (i.due_date, i.id) < ($5::date, $6::uuid))
			ORDER BY i.due_date DESC, i.id DESC
			LIMIT $7`, f.StudentIDs, f.StudentID, f.Status, f.Period, f.CursorDate, nilUUID(f.CursorID), f.Limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			i, err := scanInvoice(rows)
			if err != nil {
				return err
			}
			items = append(items, i)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar faturas: %w", err)
	}
	if len(items) > f.Limit {
		items, hasMore = items[:f.Limit], true
	}
	return items, hasMore, nil
}

func nilUUID(id string) string {
	if id == "" {
		return "00000000-0000-0000-0000-000000000000"
	}
	return id
}

func listPayments(ctx context.Context, tx pgx.Tx, invoiceID string) ([]Payment, error) {
	rows, err := tx.Query(ctx, `SELECT `+paymentColumns+` FROM payments WHERE invoice_id = $1
		ORDER BY created_at, id`, invoiceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Payment{}
	for rows.Next() {
		p, err := scanPayment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Get devolve a fatura com o histórico de pagamentos e estornos.
func (r *InvoiceRepo) Get(ctx context.Context, tenantID, id string) (Invoice, error) {
	var inv Invoice
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		if inv, err = scanInvoice(tx.QueryRow(ctx, invoiceSelect+` WHERE i.id = $1`, id)); err != nil {
			return err
		}
		inv.Payments, err = listPayments(ctx, tx, id)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Invoice{}, ErrNotFound
	}
	if err != nil {
		return Invoice{}, fmt.Errorf("repo: buscar fatura: %w", err)
	}
	return inv, nil
}

// Cancel cancela uma fatura `open` ou `overdue`; paga não cancela (estorne
// antes) e cancelada não cancela de novo.
func (r *InvoiceRepo) Cancel(ctx context.Context, tenantID, id string) (Invoice, error) {
	var inv Invoice
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM invoices WHERE id = $1 FOR UPDATE`, id).Scan(&status); err != nil {
			return err
		}
		switch status {
		case "paid":
			return ErrInvoiceAlreadyPaid
		case "canceled":
			return ErrInvoiceCanceled
		}
		if _, err := tx.Exec(ctx, `UPDATE invoices SET status = 'canceled', updated_at = now() WHERE id = $1`, id); err != nil {
			return err
		}
		var err error
		inv, err = scanInvoice(tx.QueryRow(ctx, invoiceSelect+` WHERE i.id = $1`, id))
		return err
	})
	return finishInvoice(inv, err, "cancelar fatura")
}

// RecordPaymentInput é a baixa manual. A baixa é sempre pelo valor integral
// da fatura (ADR-017 §2): o valor nunca vem do cliente.
type RecordPaymentInput struct {
	InvoiceID      string
	RecordedBy     string
	PaidAt         time.Time
	Note           *string
	IdempotencyKey *string
}

// RecordPayment grava a baixa manual e marca a fatura `paid`, na mesma
// transação e com a fatura travada (FOR UPDATE). Com Idempotency-Key já
// usada na mesma fatura devolve o pagamento original e replay=true.
func (r *InvoiceRepo) RecordPayment(ctx context.Context, tenantID string, in RecordPaymentInput) (pay Payment, inv Invoice, replay bool, err error) {
	id, err := uuid.NewV7()
	if err != nil {
		return Payment{}, Invoice{}, false, fmt.Errorf("repo: gerar id do pagamento: %w", err)
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var status string
		var amount int64
		var currency string
		if err := tx.QueryRow(ctx, `SELECT status, amount_cents, currency FROM invoices WHERE id = $1 FOR UPDATE`,
			in.InvoiceID).Scan(&status, &amount, &currency); err != nil {
			return err
		}

		if in.IdempotencyKey != nil {
			existing, err := scanPayment(tx.QueryRow(ctx, `SELECT `+paymentColumns+` FROM payments
				WHERE idempotency_key = $1`, *in.IdempotencyKey))
			if err == nil {
				if existing.InvoiceID != in.InvoiceID {
					return ErrIdempotencyConflict
				}
				pay, replay = existing, true
				inv, err = scanInvoice(tx.QueryRow(ctx, invoiceSelect+` WHERE i.id = $1`, in.InvoiceID))
				return err
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}

		switch status {
		case "paid":
			return ErrInvoiceAlreadyPaid
		case "canceled":
			return ErrInvoiceCanceled
		}

		var err error
		pay, err = scanPayment(tx.QueryRow(ctx, `
			INSERT INTO payments (id, tenant_id, invoice_id, amount_cents, currency, method, paid_at,
				recorded_by, note, idempotency_key)
			VALUES ($1, $2, $3, $4, $5, 'manual', $6, $7, $8, $9)
			RETURNING `+paymentColumns,
			id.String(), tenantID, in.InvoiceID, amount, currency, in.PaidAt, in.RecordedBy, in.Note, in.IdempotencyKey))
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE invoices SET status = 'paid', paid_at = $2, updated_at = now() WHERE id = $1`,
			in.InvoiceID, in.PaidAt); err != nil {
			return err
		}
		inv, err = scanInvoice(tx.QueryRow(ctx, invoiceSelect+` WHERE i.id = $1`, in.InvoiceID))
		return err
	})
	if err != nil {
		return Payment{}, Invoice{}, false, mapInvoiceErr(err, "registrar baixa")
	}
	return pay, inv, replay, nil
}

// ReversePayment estorna uma baixa: grava um pagamento novo com
// `reversal_of`, marca `reversed_by` no original e devolve a fatura para
// `open` ou `overdue` conforme `today` (data no fuso do tenant). Nada é
// apagado (ADR-007 §5).
func (r *InvoiceRepo) ReversePayment(ctx context.Context, tenantID, paymentID, actorID, note string, today time.Time) (reversal Payment, inv Invoice, err error) {
	id, err := uuid.NewV7()
	if err != nil {
		return Payment{}, Invoice{}, fmt.Errorf("repo: gerar id do estorno: %w", err)
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var invoiceID string
		if err := tx.QueryRow(ctx, `SELECT invoice_id FROM payments WHERE id = $1`, paymentID).Scan(&invoiceID); err != nil {
			return err
		}
		// Trava a fatura antes de ler o pagamento: dois estornos simultâneos
		// do mesmo pagamento se serializam aqui.
		var dueDate time.Time
		if err := tx.QueryRow(ctx, `SELECT due_date FROM invoices WHERE id = $1 FOR UPDATE`, invoiceID).Scan(&dueDate); err != nil {
			return err
		}
		orig, err := scanPayment(tx.QueryRow(ctx, `SELECT `+paymentColumns+` FROM payments WHERE id = $1`, paymentID))
		if err != nil {
			return err
		}
		if orig.ReversalOf != nil {
			return ErrPaymentIsReversal
		}
		if orig.ReversedBy != nil {
			return ErrPaymentAlreadyReversed
		}

		reversal, err = scanPayment(tx.QueryRow(ctx, `
			INSERT INTO payments (id, tenant_id, invoice_id, amount_cents, currency, method, provider, provider_ref,
				paid_at, recorded_by, note, reversal_of)
			VALUES ($1, $2, $3, $4, $5, $6, $7, NULL, now(), $8, $9, $10)
			RETURNING `+paymentColumns,
			id.String(), tenantID, invoiceID, orig.AmountCents, orig.Currency, orig.Method, nil, actorID, note, paymentID))
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE payments SET reversed_by = $2 WHERE id = $1`, paymentID, reversal.ID); err != nil {
			return err
		}
		back := "open"
		if dueDate.Before(today) {
			back = "overdue"
		}
		if _, err := tx.Exec(ctx, `UPDATE invoices SET status = $2, paid_at = NULL, updated_at = now() WHERE id = $1`,
			invoiceID, back); err != nil {
			return err
		}
		inv, err = scanInvoice(tx.QueryRow(ctx, invoiceSelect+` WHERE i.id = $1`, invoiceID))
		return err
	})
	if err != nil {
		return Payment{}, Invoice{}, mapInvoiceErr(err, "estornar pagamento")
	}
	return reversal, inv, nil
}

func finishInvoice(inv Invoice, err error, what string) (Invoice, error) {
	if err != nil {
		return Invoice{}, mapInvoiceErr(err, what)
	}
	return inv, nil
}

// mapInvoiceErr devolve os erros de regra como estão, traduz "sem linhas"
// em ErrNotFound e embrulha o resto.
func mapInvoiceErr(err error, what string) error {
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return ErrNotFound
	case errors.Is(err, ErrInvoiceAlreadyPaid), errors.Is(err, ErrInvoiceCanceled),
		errors.Is(err, ErrPaymentAlreadyReversed), errors.Is(err, ErrPaymentIsReversal),
		errors.Is(err, ErrIdempotencyConflict):
		return err
	case errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "uq_payments_idempotency_key":
		// Mesma chave usada em duas faturas ao mesmo tempo (cada uma travou
		// a sua): a segunda perde a inserção.
		return ErrIdempotencyConflict
	default:
		return fmt.Errorf("repo: %s: %w", what, err)
	}
}

// StudentStatuses devolve o status financeiro derivado (ADR-007 §3) de cada
// aluno: `delinquent` (existe fatura vencida), `ok` (tem assinatura) ou
// `none`. Sem coluna própria: é consulta sobre faturas.
func (r *InvoiceRepo) StudentStatuses(ctx context.Context, tenantID string, studentIDs []string) (map[string]string, error) {
	out := make(map[string]string, len(studentIDs))
	if len(studentIDs) == 0 {
		return out, nil
	}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT s.id::text,
			       CASE WHEN EXISTS (SELECT 1 FROM invoices i WHERE i.student_id = s.id AND i.status = 'overdue')
			            THEN 'delinquent'
			            WHEN EXISTS (SELECT 1 FROM subscriptions b WHERE b.student_id = s.id)
			            THEN 'ok' ELSE 'none' END
			FROM unnest($1::uuid[]) AS s(id)`, studentIDs)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id, status string
			if err := rows.Scan(&id, &status); err != nil {
				return err
			}
			out[id] = status
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: status financeiro dos alunos: %w", err)
	}
	return out, nil
}
