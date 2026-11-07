package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// TestEraseUserAnonymizesExecutionsAndUnassignsPlans cobre a exclusão de conta
// (ADR-008 §2, P4.5): execuções ficam sem titular, o plano é desatribuído e o
// estado de rotação some. É idempotente, e outro aluno do mesmo tenant não é
// tocado.
func TestEraseUserAnonymizesExecutionsAndUnassignsPlans(t *testing.T) {
	f := newExecFixture(t, "A", "B")
	ctx := context.Background()
	pool := testPool(t)
	erasure := repo.NewErasureRepo(pool)

	dayA := f.dayByLabel(t, "A")
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, execEvents(dayA.ID, f.exerciseID, 40, 45)); err != nil {
		t.Fatalf("registrar sessão: %v", err)
	}

	// Outro aluno do mesmo tenant, com plano e sessão próprios.
	otherStudent := "11111111-1111-4111-8111-111111111111"
	newPlan(t, f.plans, f.tenantID, otherStudent, "22222222-2222-4222-8222-222222222222")

	if err := erasure.EraseUser(ctx, f.tenantID, f.studentID); err != nil {
		t.Fatalf("excluir: %v", err)
	}
	// Idempotente.
	if err := erasure.EraseUser(ctx, f.tenantID, f.studentID); err != nil {
		t.Fatalf("excluir de novo: %v", err)
	}

	count := func(q string, args ...any) int {
		t.Helper()
		var n int
		err := repo.WithTenant(ctx, pool, f.tenantID, func(tx pgx.Tx) error {
			return tx.QueryRow(ctx, q, args...).Scan(&n)
		})
		if err != nil {
			t.Fatalf("contar: %v", err)
		}
		return n
	}

	if n := count(`SELECT count(*) FROM workout_sessions WHERE student_id = $1`, f.studentID); n != 0 {
		t.Fatalf("o aluno ainda é titular de %d sessões", n)
	}
	if n := count(`SELECT count(*) FROM workout_sessions WHERE student_id = $1`, repo.AnonymousUserID); n != 1 {
		t.Fatalf("a sessão deveria ter virado anônima (1), há %d", n)
	}
	// Os logs de série (append-only) seguem intactos, ligados à sessão anônima.
	if n := count(`SELECT count(*) FROM workout_set_logs l JOIN workout_sessions s ON s.id = l.session_id WHERE s.student_id = $1`, repo.AnonymousUserID); n != 2 {
		t.Fatalf("os 2 logs de série deveriam permanecer, há %d", n)
	}
	if n := count(`SELECT count(*) FROM workout_plans WHERE student_id = $1`, f.studentID); n != 0 {
		t.Fatalf("o plano ainda está atribuído ao aluno (%d)", n)
	}
	if n := count(`SELECT count(*) FROM workout_plans WHERE student_id = $1 AND title = ''`, repo.AnonymousUserID); n != 1 {
		t.Fatalf("o plano deveria estar desatribuído e sem título, há %d", n)
	}
	if _, err := f.plans.GetState(ctx, f.tenantID, f.studentID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("o estado de rotação deveria ter sido excluído: %v", err)
	}
	if n := count(`SELECT count(*) FROM workout_plans WHERE student_id = $1`, otherStudent); n != 1 {
		t.Fatalf("o outro aluno não pode ser afetado, planos=%d", n)
	}
}

// TestEraseUserIsTenantScoped: o mesmo UUID de usuário num outro tenant (RLS)
// não é tocado.
func TestEraseUserIsTenantScoped(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	pool := testPool(t)

	if err := repo.NewErasureRepo(pool).EraseUser(ctx, newTenant(), f.studentID); err != nil {
		t.Fatalf("excluir em outro tenant: %v", err)
	}
	plans, err := f.plans.ListPlansByStudent(ctx, f.tenantID, f.studentID)
	if err != nil || len(plans) != 1 {
		t.Fatalf("o plano do tenant original deveria continuar: %v %v", plans, err)
	}
}
