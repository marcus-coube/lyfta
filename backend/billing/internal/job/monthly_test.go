package job_test

import (
	"context"
	"io"
	"log/slog"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/billing/internal/job"
	"github.com/marcus-coube/lyfta/billing/internal/repo"
	"github.com/marcus-coube/lyfta/billing/internal/tenantclient"
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_billing?sslmode=disable"
	}
	pool, err := repo.NewPool(context.Background(), dsn)
	if err != nil {
		if os.Getenv("CI") != "" {
			t.Fatalf("banco indisponível no CI: %v", err)
		}
		t.Skipf("banco indisponível para teste de integração: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

type fakeTenants []tenantclient.Tenant

func (f fakeTenants) List(context.Context) ([]tenantclient.Tenant, error) { return f, nil }

// clock é um relógio fake ajustável.
type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) Now() time.Time  { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Set(t time.Time) { c.mu.Lock(); c.t = t; c.mu.Unlock() }

func newJob(pool *pgxpool.Pool, c *clock, tenants ...tenantclient.Tenant) *job.MonthlyJob {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return job.NewMonthlyJob(logger, pool, fakeTenants(tenants), repo.NewJobRepo(pool)).WithClock(c.Now)
}

// seedSub cria cliente, plano e assinatura ativa (starts_on dado).
func seedSub(t *testing.T, pool *pgxpool.Pool, tenantID, status string, dueDay int, startsOn string) string {
	t.Helper()
	studentID, planID, subID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	err := repo.WithTenant(context.Background(), pool, tenantID, func(tx pgx.Tx) error {
		ctx := context.Background()
		canceled := "NULL"
		if status == "canceled" {
			canceled = "now()"
		}
		for _, s := range []struct {
			sql  string
			args []any
		}{
			{`INSERT INTO billing_customers (tenant_id, student_id, name, email) VALUES ($1,$2,'Aluno','a@x.com')`, []any{tenantID, studentID}},
			{`INSERT INTO billing_plans (id, tenant_id, name, amount_cents) VALUES ($1,$2,'Mensal',15000)`, []any{planID, tenantID}},
			{`INSERT INTO subscriptions (id, tenant_id, student_id, billing_plan_id, amount_cents, due_day, starts_on, status, canceled_at)
			  VALUES ($1,$2,$3,$4,15000,$5,$6::date,$7,` + canceled + `)`, []any{subID, tenantID, studentID, planID, dueDay, startsOn, status}},
		} {
			if _, err := tx.Exec(ctx, s.sql, s.args...); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("seed: %v", err)
	}
	return subID
}

type inv struct{ period, due, status string }

func invoices(t *testing.T, pool *pgxpool.Pool, tenantID, subID string) []inv {
	t.Helper()
	var out []inv
	err := repo.WithTenant(context.Background(), pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(context.Background(),
			`SELECT period, due_date::text, status FROM invoices WHERE subscription_id = $1 ORDER BY period`, subID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var i inv
			if err := rows.Scan(&i.period, &i.due, &i.status); err != nil {
				return err
			}
			out = append(out, i)
		}
		return rows.Err()
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func mustLoc(t *testing.T, name string) *time.Location {
	t.Helper()
	l, err := time.LoadLocation(name)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

// Virada do mês em dois fusos: uma fatura por assinatura, vencimento no dia
// certo de cada tenant, e rodar de novo não duplica.
func TestMonthRolloverTwoTimezones(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	sp, lis := uuid.NewString(), uuid.NewString()
	subSP := seedSub(t, pool, sp, "active", 1, "2026-01-15")
	subLis := seedSub(t, pool, lis, "active", 1, "2026-01-15")
	subPaused := seedSub(t, pool, sp, "paused", 1, "2026-01-15")
	subCanceled := seedSub(t, pool, sp, "canceled", 1, "2026-01-15")
	subFuture := seedSub(t, pool, lis, "active", 5, "2026-12-01")

	c := &clock{}
	j := newJob(pool, c,
		tenantclient.Tenant{ID: sp, Timezone: "America/Sao_Paulo"},
		tenantclient.Tenant{ID: lis, Timezone: "Europe/Lisbon"})

	// 30/11 22:00 em São Paulo (= 01:00 UTC de 1/12) e 01:00 de 1/12 em Lisboa:
	// Lisboa já virou o mês, São Paulo não.
	c.Set(time.Date(2026, 11, 30, 22, 0, 0, 0, mustLoc(t, "America/Sao_Paulo")))
	j.Tick(ctx)
	if got := invoices(t, pool, sp, subSP); len(got) != 1 || got[0].period != "2026-11" || got[0].due != "2026-11-01" || got[0].status != "overdue" {
		t.Fatalf("SP em 30/11: %+v", got)
	}
	// Mesmo instante (01:00 UTC de 1/12): em Lisboa já é dezembro.
	got := invoices(t, pool, lis, subLis)
	if len(got) != 1 || got[0].period != "2026-12" || got[0].due != "2026-12-01" || got[0].status != "open" {
		t.Fatalf("Lisboa já em 1/12: %+v", got)
	}
	if got := invoices(t, pool, lis, subFuture); len(got) != 1 || got[0].period != "2026-12" || got[0].due != "2026-12-05" {
		t.Fatalf("assinatura que começa em dezembro: %+v", got)
	}

	// Rodar de novo no mesmo instante: nada muda.
	j.Tick(ctx)
	if got := invoices(t, pool, sp, subSP); len(got) != 1 {
		t.Fatalf("idempotência SP: %+v", got)
	}
	if got := invoices(t, pool, lis, subLis); len(got) != 1 {
		t.Fatalf("idempotência Lisboa: %+v", got)
	}

	// Passa a meia-noite de São Paulo: nasce dezembro (vencimento 1/12, ainda
	// não vencido em 1/12 local), novembro segue overdue.
	c.Set(time.Date(2026, 12, 1, 0, 30, 0, 0, mustLoc(t, "America/Sao_Paulo")))
	j.Tick(ctx)
	got = invoices(t, pool, sp, subSP)
	if len(got) != 2 || got[1].period != "2026-12" || got[1].due != "2026-12-01" || got[1].status != "open" {
		t.Fatalf("SP em 1/12: %+v", got)
	}
	// No dia seguinte (fuso local) a de dezembro vence.
	c.Set(time.Date(2026, 12, 2, 0, 30, 0, 0, mustLoc(t, "America/Sao_Paulo")))
	j.Tick(ctx)
	got = invoices(t, pool, sp, subSP)
	if len(got) != 2 || got[1].status != "overdue" {
		t.Fatalf("SP em 2/12: %+v", got)
	}
	// Lisboa em 2/12 01:00 UTC ainda: vencimento 1/12 já passou.
	if got := invoices(t, pool, lis, subLis); got[0].status != "overdue" {
		t.Fatalf("Lisboa em 2/12: %+v", got)
	}

	if got := invoices(t, pool, sp, subPaused); len(got) != 0 {
		t.Fatalf("pausada gerou fatura: %+v", got)
	}
	if got := invoices(t, pool, sp, subCanceled); len(got) != 0 {
		t.Fatalf("cancelada gerou fatura: %+v", got)
	}
}

// Fronteira entre fusos: o mesmo instante é dias diferentes em SP e Lisboa; o
// vencimento só passa no dia certo de cada tenant.
func TestOverdueUsesTenantTimezone(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	sp, lis := uuid.NewString(), uuid.NewString()
	subSP := seedSub(t, pool, sp, "active", 10, "2026-01-01")
	subLis := seedSub(t, pool, lis, "active", 10, "2026-01-01")
	c := &clock{}
	j := newJob(pool, c,
		tenantclient.Tenant{ID: sp, Timezone: "America/Sao_Paulo"},
		tenantclient.Tenant{ID: lis, Timezone: "Europe/Lisbon"})

	// 11/03 01:00 em Lisboa (= 10/03 22:00 em SP): vencimento dia 10.
	c.Set(time.Date(2026, 3, 11, 1, 0, 0, 0, mustLoc(t, "Europe/Lisbon")))
	j.Tick(ctx)
	if got := invoices(t, pool, sp, subSP); len(got) != 1 || got[0].status != "open" {
		t.Fatalf("SP ainda no dia 10: %+v", got)
	}
	if got := invoices(t, pool, lis, subLis); len(got) != 1 || got[0].status != "overdue" {
		t.Fatalf("Lisboa já no dia 11: %+v", got)
	}
}

// Assinatura nova não ganha período anterior ao mês de starts_on, e o
// vencimento nunca precede o início (regra de repo.DueDateFor).
func TestNoPeriodBeforeStart(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tn := uuid.NewString()
	sub := seedSub(t, pool, tn, "active", 10, "2026-11-20")
	c := &clock{}
	j := newJob(pool, c, tenantclient.Tenant{ID: tn, Timezone: "America/Sao_Paulo"})
	c.Set(time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC))
	j.Tick(ctx)
	got := invoices(t, pool, tn, sub)
	if len(got) != 1 || got[0].period != "2026-11" || got[0].due != "2026-11-20" || got[0].status != "open" {
		t.Fatalf("mês de início: %+v", got)
	}
	// Vencimento em dezembro é o due_day do mês.
	c.Set(time.Date(2026, 12, 3, 12, 0, 0, 0, time.UTC))
	j.Tick(ctx)
	got = invoices(t, pool, tn, sub)
	if len(got) != 2 || got[1].due != "2026-12-10" || got[0].status != "overdue" {
		t.Fatalf("dezembro: %+v", got)
	}
}

// Fatura paga ou cancelada não vira overdue; só open.
func TestOverdueOnlyTouchesOpen(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tn := uuid.NewString()
	sub := seedSub(t, pool, tn, "active", 1, "2026-01-01")
	c := &clock{}
	j := newJob(pool, c, tenantclient.Tenant{ID: tn, Timezone: "America/Sao_Paulo"})
	c.Set(time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC))
	j.Tick(ctx)
	if err := repo.WithTenant(ctx, pool, tn, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE invoices SET status='canceled' WHERE subscription_id=$1`, sub)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	j.Tick(ctx)
	if got := invoices(t, pool, tn, sub); len(got) != 1 || got[0].status != "canceled" {
		t.Fatalf("cancelada não pode mudar: %+v", got)
	}
}

// Duas instâncias simultâneas: com o lock já tomado por outra sessão o tick
// não faz nada; liberado, roda; e duas rodando juntas geram uma fatura só.
func TestAdvisoryLock(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tn := uuid.NewString()
	sub := seedSub(t, pool, tn, "active", 20, "2026-01-01")
	c := &clock{}
	c.Set(time.Date(2026, 11, 10, 12, 0, 0, 0, time.UTC))
	j := newJob(pool, c, tenantclient.Tenant{ID: tn, Timezone: "America/Sao_Paulo"})

	holder, err := pool.Acquire(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var ok bool
	if err := holder.QueryRow(ctx, `SELECT pg_try_advisory_lock(hashtext('lyfta_billing_monthly_job'))`).Scan(&ok); err != nil || !ok {
		t.Fatalf("lock de teste: %v %v", ok, err)
	}
	j.Tick(ctx)
	if got := invoices(t, pool, tn, sub); len(got) != 0 {
		t.Fatalf("tick rodou com o lock tomado: %+v", got)
	}
	if _, err := holder.Exec(ctx, `SELECT pg_advisory_unlock(hashtext('lyfta_billing_monthly_job'))`); err != nil {
		t.Fatal(err)
	}
	holder.Release()

	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() { defer wg.Done(); j.Tick(ctx) }()
	}
	wg.Wait()
	if got := invoices(t, pool, tn, sub); len(got) != 1 {
		t.Fatalf("esperava 1 fatura, veio %+v", got)
	}
}
