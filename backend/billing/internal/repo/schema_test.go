package repo_test

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/billing/internal/repo"
)

// testPool abre o pool contra o Postgres de dev (lyfta_billing, migrations já
// aplicadas), como lyfta_app — sem BYPASSRLS, senão o RLS não vale. Fora do CI
// pula se o banco não estiver acessível; no CI o ambiente é obrigatório.
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

func newID() string { return uuid.NewString() }

// seed cria cliente, plano, assinatura e uma fatura aberta no tenant. Devolve
// os ids (student, subscription, invoice).
func seed(t *testing.T, pool *pgxpool.Pool, tenantID string) (studentID, subID, invoiceID string) {
	var planID string
	t.Helper()
	studentID, planID, subID, invoiceID = newID(), newID(), newID(), newID()
	err := repo.WithTenant(context.Background(), pool, tenantID, func(tx pgx.Tx) error {
		ctx := context.Background()
		stmts := []struct {
			sql  string
			args []any
		}{
			{`INSERT INTO billing_customers (tenant_id, student_id, name, email) VALUES ($1,$2,'Aluna','a@x.com')`,
				[]any{tenantID, studentID}},
			{`INSERT INTO billing_plans (id, tenant_id, name, amount_cents) VALUES ($1,$2,'Mensal',15000)`,
				[]any{planID, tenantID}},
			{`INSERT INTO subscriptions (id, tenant_id, student_id, billing_plan_id, amount_cents, due_day, starts_on)
			  VALUES ($1,$2,$3,$4,15000,10,CURRENT_DATE)`, []any{subID, tenantID, studentID, planID}},
			{`INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents)
			  VALUES ($1,$2,$3,$4,'2026-11',CURRENT_DATE,15000)`, []any{invoiceID, tenantID, subID, studentID}},
		}
		for _, s := range stmts {
			if _, err := tx.Exec(ctx, s.sql, s.args...); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("seed: %v", err)
	}
	return studentID, subID, invoiceID
}

func exec(pool *pgxpool.Pool, tenantID, sql string, args ...any) error {
	return repo.WithTenant(context.Background(), pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(context.Background(), sql, args...)
		return err
	})
}

var tenantTables = []string{
	"billing_customers", "billing_plans", "subscriptions", "invoices",
	"payments", "payment_provider_events",
}

// Isolamento (ADR-001): o tenant B não enxerga nada do A nas 6 tabelas, e o
// RLS é forçado em todas.
func TestCrossTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newID(), newID()
	_, _, invoiceID := seed(t, pool, tenantA)
	if err := exec(pool, tenantA, `INSERT INTO payments (id, tenant_id, invoice_id, amount_cents, method, paid_at, recorded_by)
		VALUES ($1,$2,$3,15000,'manual',now(),$4)`, newID(), tenantA, invoiceID, newID()); err != nil {
		t.Fatalf("gravar payment: %v", err)
	}
	if err := exec(pool, tenantA, `INSERT INTO payment_provider_events (id, tenant_id, provider, event_id, payload)
		VALUES ($1,$2,'asaas','evt-1','{}')`, newID(), tenantA); err != nil {
		t.Fatalf("gravar evento: %v", err)
	}

	count := func(tenant, table string) (n int) {
		err := repo.WithTenant(ctx, pool, tenant, func(tx pgx.Tx) error {
			return tx.QueryRow(ctx, "SELECT count(*) FROM "+table).Scan(&n)
		})
		if err != nil {
			t.Fatalf("contar %s: %v", table, err)
		}
		return n
	}
	for _, table := range tenantTables {
		if got := count(tenantA, table); got != 1 {
			t.Errorf("%s: A deveria ver 1 linha, viu %d", table, got)
		}
		if got := count(tenantB, table); got != 0 {
			t.Errorf("vazamento: B viu %d linha(s) de %s do tenant A", got, table)
		}
	}

	var forced int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM pg_class
		WHERE relname = ANY($1) AND relrowsecurity AND relforcerowsecurity`, tenantTables).Scan(&forced); err != nil {
		t.Fatal(err)
	}
	if forced != len(tenantTables) {
		t.Errorf("RLS forçada em %d de %d tabelas", forced, len(tenantTables))
	}

	// B também não grava em nome do A.
	err := exec(pool, tenantB, `INSERT INTO billing_plans (id, tenant_id, name, amount_cents) VALUES ($1,$2,'x',100)`, newID(), tenantA)
	if err == nil {
		t.Error("tenant B conseguiu gravar linha com tenant_id do A")
	}
	// Sem contexto de tenant, a escrita é recusada.
	if _, err := pool.Exec(ctx, `INSERT INTO billing_plans (id, tenant_id, name, amount_cents) VALUES ($1,$2,'x',100)`, newID(), tenantA); err == nil {
		t.Error("insert sem app.tenant_id deveria ser recusado")
	}
}

// Fatura paga é imutável (ADR-007 §2): só estorno a reabre.
func TestPaidInvoiceIsImmutable(t *testing.T) {
	pool := testPool(t)
	tenant := newID()
	_, _, inv := seed(t, pool, tenant)

	if err := exec(pool, tenant, `UPDATE invoices SET status='paid', paid_at=now() WHERE id=$1`, inv); err != nil {
		t.Fatalf("pagar fatura aberta deve ser permitido: %v", err)
	}
	blocked := map[string]string{
		"alterar valor":              `UPDATE invoices SET amount_cents = 1 WHERE id=$1`,
		"alterar vencimento":         `UPDATE invoices SET due_date = due_date + 1 WHERE id=$1`,
		"cancelar":                   `UPDATE invoices SET status='canceled', paid_at=NULL WHERE id=$1`,
		"reabrir sem limpar paid_at": `UPDATE invoices SET status='open' WHERE id=$1`,
		"apagar":                     `DELETE FROM invoices WHERE id=$1`,
	}
	for name, sql := range blocked {
		if err := exec(pool, tenant, sql, inv); err == nil {
			t.Errorf("%s: fatura paga não deveria mudar", name)
		}
	}
	// Estorno: volta a open limpando paid_at, sem tocar nos demais campos.
	if err := exec(pool, tenant, `UPDATE invoices SET status='overdue', paid_at=NULL WHERE id=$1`, inv); err != nil {
		t.Fatalf("estorno (paid → overdue) deve ser permitido: %v", err)
	}
	// Depois de reaberta volta a ser editável.
	if err := exec(pool, tenant, `UPDATE invoices SET status='canceled' WHERE id=$1`, inv); err != nil {
		t.Fatalf("fatura reaberta deve aceitar cancelamento: %v", err)
	}
}

// payments é append-only; a única mudança permitida é preencher reversed_by.
func TestPaymentsAppendOnly(t *testing.T) {
	pool := testPool(t)
	tenant := newID()
	_, _, inv := seed(t, pool, tenant)
	orig, reversal, user := newID(), newID(), newID()

	if err := exec(pool, tenant, `INSERT INTO payments (id, tenant_id, invoice_id, amount_cents, method, paid_at, recorded_by)
		VALUES ($1,$2,$3,15000,'manual',now(),$4)`, orig, tenant, inv, user); err != nil {
		t.Fatal(err)
	}
	for name, sql := range map[string]string{
		"alterar valor": `UPDATE payments SET amount_cents = 1 WHERE id=$1`,
		"alterar nota":  `UPDATE payments SET note = 'x' WHERE id=$1`,
		"apagar":        `DELETE FROM payments WHERE id=$1`,
	} {
		if err := exec(pool, tenant, sql, orig); err == nil {
			t.Errorf("%s: payment não deveria mudar", name)
		}
	}
	// Estorno = novo registro + reversed_by no original.
	if err := exec(pool, tenant, `INSERT INTO payments (id, tenant_id, invoice_id, amount_cents, method, paid_at, recorded_by, reversal_of)
		VALUES ($1,$2,$3,15000,'manual',now(),$4,$5)`, reversal, tenant, inv, user, orig); err != nil {
		t.Fatalf("gravar estorno: %v", err)
	}
	if err := exec(pool, tenant, `UPDATE payments SET reversed_by=$2 WHERE id=$1`, orig, reversal); err != nil {
		t.Fatalf("marcar reversed_by: %v", err)
	}
	if err := exec(pool, tenant, `UPDATE payments SET reversed_by=NULL WHERE id=$1`, orig); err == nil {
		t.Error("reversed_by não pode ser desfeito")
	}
}

func TestOneLiveSubscriptionPerStudent(t *testing.T) {
	pool := testPool(t)
	tenant := newID()
	student, sub, _ := seed(t, pool, tenant)

	var plan string
	err := repo.WithTenant(context.Background(), pool, tenant, func(tx pgx.Tx) error {
		return tx.QueryRow(context.Background(), `SELECT billing_plan_id FROM subscriptions WHERE id=$1`, sub).Scan(&plan)
	})
	if err != nil {
		t.Fatal(err)
	}
	insert := `INSERT INTO subscriptions (id, tenant_id, student_id, billing_plan_id, amount_cents, due_day, starts_on)
		VALUES ($1,$2,$3,$4,15000,5,CURRENT_DATE)`
	if err := exec(pool, tenant, insert, newID(), tenant, student, plan); err == nil {
		t.Error("segunda assinatura vigente do mesmo aluno deveria ser recusada")
	}
	if err := exec(pool, tenant, `UPDATE subscriptions SET status='canceled', canceled_at=$2 WHERE id=$1`, sub, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := exec(pool, tenant, insert, newID(), tenant, student, plan); err != nil {
		t.Errorf("com a anterior cancelada a nova deve ser aceita: %v", err)
	}
	// Faturas: um mês, uma fatura por assinatura.
	if err := exec(pool, tenant, `INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents)
		VALUES ($1,$2,$3,$4,'2026-11',CURRENT_DATE,15000)`, newID(), tenant, sub, student); err == nil {
		t.Error("período duplicado na mesma assinatura deveria ser recusado")
	}
}

// ADR-007 §1: nenhuma coluna monetária pode ser decimal/float — o schema
// inteiro do billing só tem inteiros para dinheiro.
func TestNoFloatingMoneyColumns(t *testing.T) {
	pool := testPool(t)
	rows, err := pool.Query(context.Background(), `
		SELECT table_name, column_name, data_type FROM information_schema.columns
		WHERE table_schema = 'public'`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	money := 0
	for rows.Next() {
		var table, col, typ string
		if err := rows.Scan(&table, &col, &typ); err != nil {
			t.Fatal(err)
		}
		switch typ {
		case "numeric", "real", "double precision", "money":
			t.Errorf("%s.%s é %s: dinheiro e demais valores são inteiros no billing", table, col, typ)
		}
		if strings.HasSuffix(col, "_cents") {
			money++
			if typ != "bigint" {
				t.Errorf("%s.%s deveria ser bigint, é %s", table, col, typ)
			}
		}
	}
	if money == 0 {
		t.Error("nenhuma coluna *_cents encontrada: o teste não está varrendo o schema certo")
	}
}
