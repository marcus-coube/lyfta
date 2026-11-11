package repo_test

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// testPool abre um pool contra o Postgres de dev (lyfta_assessment, migrations
// já aplicadas). Sem DATABASE_URL configurada explicitamente, usa o mesmo
// default documentado em backend/assessment/.env.example. Fora do CI, pula o
// teste se o banco não estiver acessível — mantém `go test ./...` rodável
// sem Postgres.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		// lyfta_app: role sem BYPASSRLS (migration 0004_app_role) — RLS não
		// tem efeito nenhum se o teste conectar como superusuário (postgres).
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_assessment?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		// No CI (P0.7) o Postgres é service container obrigatório: pular aqui
		// deixaria o pipeline verde sem ter testado nada.
		skipOrFail(t, "banco indisponível para teste de integração: "+err.Error())
	}
	t.Cleanup(pool.Close)
	return pool
}

// skipOrFail pula o teste fora do CI e falha dentro dele: no CI o ambiente
// (Postgres) é obrigatório, e pular deixaria o pipeline verde sem ter testado
// nada (P0.7).
func skipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// newID devolve um UUID novo. Não existe tabela de tenants/usuários neste
// banco: tenant e aluno vivem no identity e chegam aqui só como UUID
// (ADR-013 §2).
func newID() string { return uuid.NewString() }

// insertBodyMeasurement grava uma medida sob o tenant informado (via
// repo.WithTenant, o mesmo caminho que a API da P2.3 vai usar).
func insertBodyMeasurement(ctx context.Context, pool *pgxpool.Pool, tenantID, studentID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO body_measurements (id, tenant_id, student_id, measured_at, weight_kg, waist_cm, created_by)
			VALUES ($1, $2, $3, CURRENT_DATE, 80.5, 90.2, $3)`,
			uuid.NewString(), tenantID, studentID)
		return err
	})
}

func insertBioimpedanceRecord(ctx context.Context, pool *pgxpool.Pool, tenantID, studentID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO bioimpedance_records (id, tenant_id, student_id, measured_at, body_fat_pct, bmr_kcal, created_by)
			VALUES ($1, $2, $3, CURRENT_DATE, 18.4, 1800, $3)`,
			uuid.NewString(), tenantID, studentID)
		return err
	})
}

func insertProgressPhoto(ctx context.Context, pool *pgxpool.Pool, tenantID, studentID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO progress_photos (id, tenant_id, student_id, taken_at, pose, media_key, created_by)
			VALUES ($1, $2, $3, CURRENT_DATE, 'front', $4, $3)`,
			uuid.NewString(), tenantID, studentID,
			"tenants/"+tenantID+"/students/"+studentID+"/photos/"+uuid.NewString()+".jpg")
		return err
	})
}

// countRows conta as linhas que o tenant informado enxerga na tabela — o RLS
// filtra antes de qualquer contagem chegar ao Go.
func countRows(ctx context.Context, pool *pgxpool.Pool, tenantID, table string) (int, error) {
	var n int
	err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, "SELECT count(*) FROM "+table).Scan(&n)
	})
	return n, err
}

// TestCrossTenantIsolation cobre o Aceite da P2.2 e o ADR-001 §6: o tenant B
// não enxerga as medidas, a bioimpedância nem as fotos do tenant A, e o
// próprio tenant A continua enxergando o que gravou.
func TestCrossTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newID(), newID()
	studentA := newID()

	if err := insertBodyMeasurement(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar medida do A: %v", err)
	}
	if err := insertBioimpedanceRecord(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar bioimpedância do A: %v", err)
	}
	if err := insertProgressPhoto(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar foto do A: %v", err)
	}

	for _, table := range []string{"body_measurements", "bioimpedance_records", "progress_photos"} {
		gotA, err := countRows(ctx, pool, tenantA, table)
		if err != nil {
			t.Fatalf("contar %s como A: %v", table, err)
		}
		if gotA != 1 {
			t.Fatalf("%s: A deveria ver o próprio registro, viu %d", table, gotA)
		}

		gotB, err := countRows(ctx, pool, tenantB, table)
		if err != nil {
			t.Fatalf("contar %s como B: %v", table, err)
		}
		if gotB != 0 {
			t.Fatalf("vazamento entre tenants: B viu %d linha(s) de %s do tenant A", gotB, table)
		}
	}
}

// TestRLSBlocksWriteWithoutTenantContext cobre ADR-001 §2: sem
// `app.tenant_id` setado (fora de repo.WithTenant), a policy recusa a
// escrita — a aplicação não pode gravar um fato sem tenant.
func TestRLSBlocksWriteWithoutTenantContext(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newID()

	_, err := pool.Exec(ctx, `
		INSERT INTO body_measurements (id, tenant_id, student_id, measured_at, weight_kg, created_by)
		VALUES ($1, $2, $3, CURRENT_DATE, 70, $3)`,
		uuid.NewString(), tenantID, newID())
	if err == nil {
		t.Fatal("insert sem app.tenant_id setado deveria ser recusado pelo RLS")
	}
}
