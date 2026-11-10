// Package job roda o job do financeiro (P7.3): a cada tick de 15 min, uma
// única instância por vez (pg_try_advisory_lock) varre os tenants — lista do
// identity por M2M, cache de 10 min — e, no fuso de cada um, garante a fatura
// do mês corrente das assinaturas `active` e vira `overdue` as faturas `open`
// vencidas. Idempotente: rodar duas vezes no mesmo dia não duplica nada.
package job

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/billing/internal/tenantclient"
	"github.com/marcus-coube/lyfta/billing/internal/tenantsettings"
)

// lockKey é o nome hasheado (hashtext) do advisory lock; não é id de negócio.
const lockKey = "lyfta_billing_monthly_job"

// TickInterval é o intervalo entre varreduras.
const TickInterval = 15 * time.Minute

type tenantSource interface {
	List(ctx context.Context) ([]tenantclient.Tenant, error)
}

type invoiceJobs interface {
	GenerateInvoices(ctx context.Context, tenantID string, today time.Time) (int, error)
	MarkOverdue(ctx context.Context, tenantID string, today time.Time) (int, error)
}

// MonthlyJob é o job de geração mensal e vencimento.
type MonthlyJob struct {
	logger  *slog.Logger
	pool    *pgxpool.Pool
	tenants tenantSource
	jobs    invoiceJobs
	now     func() time.Time
}

// NewMonthlyJob cria o job.
func NewMonthlyJob(logger *slog.Logger, pool *pgxpool.Pool, tenants tenantSource, jobs invoiceJobs) *MonthlyJob {
	return &MonthlyJob{logger: logger, pool: pool, tenants: tenants, jobs: jobs, now: time.Now}
}

// WithClock troca o relógio (Clock injetável, só para teste).
func (j *MonthlyJob) WithClock(now func() time.Time) *MonthlyJob {
	j.now = now
	return j
}

// Run varre na subida e a cada TickInterval até o contexto acabar.
func (j *MonthlyJob) Run(ctx context.Context) {
	j.Tick(ctx)
	ticker := time.NewTicker(TickInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			j.Tick(ctx)
		}
	}
}

// Tick faz uma varredura. Não bloqueia: se outra instância segura o lock,
// volta sem fazer nada. O lock é de sessão, então fica numa conexão
// dedicada, liberada ao fim.
func (j *MonthlyJob) Tick(ctx context.Context) {
	conn, err := j.pool.Acquire(ctx)
	if err != nil {
		j.logger.Error("billing_job_acquire_failed", slog.Any("error", err))
		return
	}
	defer conn.Release()

	var locked bool
	if err := conn.QueryRow(ctx, `SELECT pg_try_advisory_lock(hashtext($1))`, lockKey).Scan(&locked); err != nil {
		j.logger.Error("billing_job_lock_failed", slog.Any("error", err))
		return
	}
	if !locked {
		j.logger.Debug("billing_job_skipped", slog.String("reason", "outra instância segura o lock"))
		return
	}
	defer func() {
		// Contexto novo: se o ctx foi cancelado o unlock ainda precisa sair
		// (e a conexão volta limpa ao pool).
		uctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, err := conn.Exec(uctx, `SELECT pg_advisory_unlock(hashtext($1))`, lockKey); err != nil {
			j.logger.Error("billing_job_unlock_failed", slog.Any("error", err))
			_ = conn.Hijack().Close(uctx) // sem unlock, descarta a sessão para soltar o lock
		}
	}()

	tenants, err := j.tenants.List(ctx)
	if err != nil {
		j.logger.Error("billing_job_list_tenants_failed", slog.Any("error", err))
		return
	}
	for _, t := range tenants {
		if ctx.Err() != nil {
			return
		}
		j.sweepTenant(ctx, t)
	}
}

// sweepTenant roda geração e vencimento do tenant na data civil local.
// Falha em um tenant não impede os demais; o próximo tick refaz.
func (j *MonthlyJob) sweepTenant(ctx context.Context, t tenantclient.Tenant) {
	loc := tenantsettings.Settings{Timezone: t.Timezone}.Location()
	local := j.now().In(loc)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, time.UTC)

	created, err := j.jobs.GenerateInvoices(ctx, t.ID, today)
	if err != nil {
		j.logger.Error("billing_job_generate_failed", slog.String("tenant_id", t.ID), slog.Any("error", err))
		return
	}
	overdue, err := j.jobs.MarkOverdue(ctx, t.ID, today)
	if err != nil {
		j.logger.Error("billing_job_overdue_failed", slog.String("tenant_id", t.ID), slog.Any("error", err))
		return
	}
	if created > 0 || overdue > 0 {
		j.logger.Info("billing_job_swept", slog.String("tenant_id", t.ID),
			slog.Int("invoices_created", created), slog.Int("invoices_overdue", overdue))
	}
}
