package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// As duas linhas de student_plan_state abaixo não passam por Publish (que
// exige a árvore completa, ver assertVersionComplete): o critério de "plano
// ativo" que find_pending_students usa é só a existência da linha, o mesmo
// que GetState já assume em todo o resto do serviço — inserir direto, mesmo
// truque de TestSetLogsAreAppendOnly, é suficiente e mais simples.

func TestPendingStudentsOfRequestedTenant(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	plans := repo.NewPlanRepo(pool)
	pending := repo.NewPendingRepo(pool)

	tenantID := newTenant()
	studentID := uuid.NewString()

	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: uuid.NewString(), Title: "Plano ativo",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	if _, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0,
	}); err != nil {
		t.Fatalf("criar dia: %v", err)
	}

	// student_plan_state: mesmo critério de "plano ativo" usado pelo resto do
	// serviço (GetState) — a linha existe, sem reconferir workout_plans.status.
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id)
			VALUES ($1, $2, $3, $4)`,
			tenantID, studentID, plan.ID, version.ID)
		return err
	}); err != nil {
		t.Fatalf("gravar student_plan_state: %v", err)
	}

	since := time.Now().Add(-time.Hour)
	until := time.Now().Add(time.Hour)

	items, err := pending.PendingStudents(ctx, since, until, []string{tenantID})
	if err != nil {
		t.Fatalf("consultar pendentes: %v", err)
	}
	if !containsPending(items, tenantID, studentID) {
		t.Fatalf("aluno com plano ativo e sem sessão deveria aparecer como pendente, veio %+v", items)
	}
}

func TestPendingStudentsExcludesWhoTrainedInRange(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	plans := repo.NewPlanRepo(pool)
	pending := repo.NewPendingRepo(pool)

	tenantID := newTenant()
	studentID := uuid.NewString()

	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: uuid.NewString(), Title: "Plano ativo",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	day, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0,
	})
	if err != nil {
		t.Fatalf("criar dia: %v", err)
	}
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id)
			VALUES ($1, $2, $3, $4)`,
			tenantID, studentID, plan.ID, version.ID)
		return err
	}); err != nil {
		t.Fatalf("gravar student_plan_state: %v", err)
	}

	since := time.Now().Add(-time.Hour)
	until := time.Now().Add(time.Hour)

	// Sessão registrada agora (received_at = now(), dentro do intervalo) —
	// depois disso o aluno não é mais "pendente" nesse intervalo.
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO workout_sessions (id, tenant_id, student_id, plan_version_id, day_id, snapshot, client_id)
			VALUES ($1, $2, $3, $4, $5, '{}'::jsonb, $6)`,
			uuid.NewString(), tenantID, studentID, version.ID, day.ID, uuid.NewString())
		return err
	}); err != nil {
		t.Fatalf("gravar sessão: %v", err)
	}

	items, err := pending.PendingStudents(ctx, since, until, []string{tenantID})
	if err != nil {
		t.Fatalf("consultar pendentes: %v", err)
	}
	if containsPending(items, tenantID, studentID) {
		t.Fatalf("aluno que treinou dentro do intervalo não deveria aparecer como pendente, veio %+v", items)
	}
}

// TestPendingStudentsOnlyRequestedTenants: aluno pendente de um tenant que
// não foi pedido não aparece (P5.1 — a consulta deixou de ser cross-tenant).
func TestPendingStudentsOnlyRequestedTenants(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	plans := repo.NewPlanRepo(pool)
	pending := repo.NewPendingRepo(pool)

	tenantID := newTenant()
	studentID := uuid.NewString()

	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: uuid.NewString(), Title: "Plano ativo",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id)
			VALUES ($1, $2, $3, $4)`,
			tenantID, studentID, plan.ID, version.ID)
		return err
	}); err != nil {
		t.Fatalf("gravar student_plan_state: %v", err)
	}

	since := time.Now().Add(-time.Hour)
	until := time.Now().Add(time.Hour)

	items, err := pending.PendingStudents(ctx, since, until, []string{newTenant()})
	if err != nil {
		t.Fatalf("consultar pendentes: %v", err)
	}
	if containsPending(items, tenantID, studentID) {
		t.Fatalf("aluno de tenant não pedido não deveria aparecer, veio %+v", items)
	}
	for _, it := range items {
		if it.TenantID == tenantID {
			t.Fatalf("veio item de tenant não pedido: %+v", it)
		}
	}

	none, err := pending.PendingStudents(ctx, since, until, nil)
	if err != nil {
		t.Fatalf("consultar pendentes sem tenants: %v", err)
	}
	if len(none) != 0 {
		t.Fatalf("lista de tenants vazia deveria devolver nada, veio %+v", none)
	}
}

func containsPending(items []repo.PendingStudent, tenantID, studentID string) bool {
	for _, it := range items {
		if it.TenantID == tenantID && it.StudentID == studentID {
			return true
		}
	}
	return false
}
