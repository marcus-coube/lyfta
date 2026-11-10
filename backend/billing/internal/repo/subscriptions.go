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

// Customer é a cópia do titular (`billing_customers`, ADR-017 §5): nome e
// e-mail tirados do identity ao assinar. Depois da exclusão da conta o
// registro fica, com `account_deleted`.
type Customer struct {
	Name           string `json:"name"`
	Email          string `json:"email"`
	AccountDeleted bool   `json:"account_deleted"`
}

// Subscription é o vínculo aluno↔plano de mensalidade (ADR-007 §2).
type Subscription struct {
	ID            string     `json:"id"`
	StudentID     string     `json:"student_id"`
	BillingPlanID string     `json:"billing_plan_id"`
	AmountCents   int64      `json:"amount_cents"`
	Currency      string     `json:"currency"`
	DueDay        int        `json:"due_day"`
	StartsOn      string     `json:"starts_on"`
	Status        string     `json:"status"`
	CanceledAt    *time.Time `json:"canceled_at"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	Customer      Customer   `json:"customer"`
}

const subscriptionSelect = `
	SELECT s.id, s.student_id, s.billing_plan_id, s.amount_cents, s.currency, s.due_day,
	       s.starts_on::text, s.status, s.canceled_at, s.created_at, s.updated_at,
	       c.name, c.email, c.account_deleted_at IS NOT NULL
	FROM subscriptions s
	JOIN billing_customers c ON c.tenant_id = s.tenant_id AND c.student_id = s.student_id`

func scanSubscription(row pgx.Row) (Subscription, error) {
	var s Subscription
	err := row.Scan(&s.ID, &s.StudentID, &s.BillingPlanID, &s.AmountCents, &s.Currency, &s.DueDay,
		&s.StartsOn, &s.Status, &s.CanceledAt, &s.CreatedAt, &s.UpdatedAt,
		&s.Customer.Name, &s.Customer.Email, &s.Customer.AccountDeleted)
	return s, err
}

// SubscriptionRepo dá acesso a subscriptions (e à cópia do titular).
type SubscriptionRepo struct{ pool *pgxpool.Pool }

// NewSubscriptionRepo cria o repositório de assinaturas.
func NewSubscriptionRepo(pool *pgxpool.Pool) *SubscriptionRepo {
	return &SubscriptionRepo{pool: pool}
}

// CreateSubscriptionInput reúne o que o handler já validou. Today e StartsOn
// são datas (00:00 UTC) no calendário do tenant.
type CreateSubscriptionInput struct {
	StudentID     string
	StudentName   string
	StudentEmail  string
	BillingPlanID string
	AmountCents   *int64 // nil = valor do plano
	DueDay        int
	StartsOn      time.Time
	Today         time.Time
}

// DueDateFor é o vencimento do período (ano/mês de `month`): o `due_day` do
// mês, nunca antes do início da assinatura — quem assina dia 20 com
// vencimento dia 10 não nasce inadimplente. Regra compartilhada com o job
// mensal (P7.3).
func DueDateFor(month time.Time, dueDay int, startsOn time.Time) time.Time {
	due := time.Date(month.Year(), month.Month(), dueDay, 0, 0, 0, 0, time.UTC)
	if due.Before(startsOn) {
		return startsOn
	}
	return due
}

// Create grava a cópia do titular, a assinatura e, se `starts_on` cair no
// mês corrente do tenant, a fatura desse período — tudo na mesma transação.
func (r *SubscriptionRepo) Create(ctx context.Context, tenantID string, in CreateSubscriptionInput) (Subscription, *Invoice, error) {
	subID, err := uuid.NewV7()
	if err != nil {
		return Subscription{}, nil, fmt.Errorf("repo: gerar id da assinatura: %w", err)
	}
	var sub Subscription
	var first *Invoice
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var planAmount int64
		var active bool
		err := tx.QueryRow(ctx, `SELECT amount_cents, active FROM billing_plans WHERE id = $1`,
			in.BillingPlanID).Scan(&planAmount, &active)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if !active {
			return ErrPlanArchived
		}
		amount := planAmount
		if in.AmountCents != nil {
			amount = *in.AmountCents
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO billing_customers (tenant_id, student_id, name, email)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (tenant_id, student_id)
			DO UPDATE SET name = EXCLUDED.name, email = EXCLUDED.email, updated_at = now()`,
			tenantID, in.StudentID, in.StudentName, in.StudentEmail); err != nil {
			return err
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO subscriptions (id, tenant_id, student_id, billing_plan_id, amount_cents, due_day, starts_on)
			VALUES ($1, $2, $3, $4, $5, $6, $7::date)`,
			subID.String(), tenantID, in.StudentID, in.BillingPlanID, amount, in.DueDay,
			in.StartsOn.Format(time.DateOnly)); err != nil {
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				return ErrSubscriptionExists
			}
			return err
		}

		if in.StartsOn.Year() == in.Today.Year() && in.StartsOn.Month() == in.Today.Month() {
			due := DueDateFor(in.Today, in.DueDay, in.StartsOn)
			status := "open"
			if due.Before(in.Today) {
				status = "overdue"
			}
			inv, err := insertInvoice(ctx, tx, tenantID, subID.String(), in.StudentID,
				in.Today.Format("2006-01"), due, amount, status)
			if err != nil {
				return err
			}
			first = &inv
		}
		sub, err = scanSubscription(tx.QueryRow(ctx, subscriptionSelect+` WHERE s.id = $1`, subID.String()))
		if err != nil {
			return err
		}
		if first != nil {
			first.Customer = sub.Customer
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, ErrNotFound) || errors.Is(err, ErrPlanArchived) || errors.Is(err, ErrSubscriptionExists) {
			return Subscription{}, nil, err
		}
		return Subscription{}, nil, fmt.Errorf("repo: criar assinatura: %w", err)
	}
	return sub, first, nil
}

// Get devolve a assinatura (ErrNotFound se não existe no tenant).
func (r *SubscriptionRepo) Get(ctx context.Context, tenantID, id string) (Subscription, error) {
	var s Subscription
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		s, err = scanSubscription(tx.QueryRow(ctx, subscriptionSelect+` WHERE s.id = $1`, id))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	if err != nil {
		return Subscription{}, fmt.Errorf("repo: buscar assinatura: %w", err)
	}
	return s, nil
}

// List devolve as assinaturas, mais novas primeiro. studentIDs limita o
// conjunto (nil = todos; vazio = nenhum, o coach sem alunos); studentID e
// status são filtros opcionais.
func (r *SubscriptionRepo) List(ctx context.Context, tenantID string, studentIDs []string, studentID, status string) ([]Subscription, error) {
	items := []Subscription{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, subscriptionSelect+`
			WHERE ($1::uuid[] IS NULL OR s.student_id = ANY($1))
			  AND ($2 = '' OR s.student_id = $2::uuid)
			  AND ($3 = '' OR s.status = $3)
			ORDER BY s.created_at DESC, s.id DESC LIMIT 200`, studentIDs, studentID, status)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			s, err := scanSubscription(rows)
			if err != nil {
				return err
			}
			items = append(items, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar assinaturas: %w", err)
	}
	return items, nil
}

// Patch altera valor e/ou vencimento. Só vale para as **próximas** faturas:
// as já geradas não mudam (ADR-007: a fatura é o registro do que foi cobrado).
func (r *SubscriptionRepo) Patch(ctx context.Context, tenantID, id string, amountCents *int64, dueDay *int) (Subscription, error) {
	var s Subscription
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM subscriptions WHERE id = $1 FOR UPDATE`, id).Scan(&status); err != nil {
			return err
		}
		if status == "canceled" {
			return &StateError{Status: status}
		}
		if _, err := tx.Exec(ctx, `UPDATE subscriptions SET
				amount_cents = COALESCE($2, amount_cents), due_day = COALESCE($3, due_day), updated_at = now()
			WHERE id = $1`, id, amountCents, dueDay); err != nil {
			return err
		}
		var err error
		s, err = scanSubscription(tx.QueryRow(ctx, subscriptionSelect+` WHERE s.id = $1`, id))
		return err
	})
	return finishTransition(s, err, "atualizar assinatura")
}

// Ações de ciclo de vida da assinatura.
const (
	ActionPause  = "pause"
	ActionResume = "resume"
	ActionCancel = "cancel"
)

// StateError carrega o estado atual numa transição inválida; casa com
// ErrInvalidState por errors.Is.
type StateError struct{ Status string }

func (e *StateError) Error() string { return "repo: transição inválida a partir de " + e.Status }
func (e *StateError) Is(target error) bool {
	return target == ErrInvalidState
}

// Transition aplica pause|resume|cancel. Cancelar cancela também as faturas
// `open` com vencimento depois de `today`; as vencidas e as pagas ficam.
func (r *SubscriptionRepo) Transition(ctx context.Context, tenantID, id, action string, today time.Time) (Subscription, error) {
	var s Subscription
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM subscriptions WHERE id = $1 FOR UPDATE`, id).Scan(&status); err != nil {
			return err
		}
		var to string
		switch {
		case action == ActionPause && status == "active":
			to = "paused"
		case action == ActionResume && status == "paused":
			to = "active"
		case action == ActionCancel && (status == "active" || status == "paused"):
			to = "canceled"
		default:
			return &StateError{Status: status}
		}
		if to == "canceled" {
			if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status = 'canceled', canceled_at = now(), updated_at = now() WHERE id = $1`, id); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `UPDATE invoices SET status = 'canceled', updated_at = now()
				WHERE subscription_id = $1 AND status = 'open' AND due_date > $2::date`,
				id, today.Format(time.DateOnly)); err != nil {
				return err
			}
		} else if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status = $2, updated_at = now() WHERE id = $1`, id, to); err != nil {
			return err
		}
		var err error
		s, err = scanSubscription(tx.QueryRow(ctx, subscriptionSelect+` WHERE s.id = $1`, id))
		return err
	})
	return finishTransition(s, err, "mudar estado da assinatura")
}

func finishTransition(s Subscription, err error, what string) (Subscription, error) {
	var stateErr *StateError
	switch {
	case err == nil:
		return s, nil
	case errors.Is(err, pgx.ErrNoRows):
		return Subscription{}, ErrNotFound
	case errors.As(err, &stateErr):
		return Subscription{}, err
	default:
		return Subscription{}, fmt.Errorf("repo: %s: %w", what, err)
	}
}
