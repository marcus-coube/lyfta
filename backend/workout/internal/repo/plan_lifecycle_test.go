package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// Duplicar, arquivar, ativar e listar versões são do tenant: outro tenant não
// enxerga o plano (RLS) — nada vaza pelo ciclo de vida.
func TestPlanLifecycleTenantIsolated(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantA)
	coach, student := uuid.NewString(), uuid.NewString()

	plan, err := plans.CreatePlan(ctx, domain.Plan{TenantID: tenantA, StudentID: student, CoachID: coach, Title: "P"})
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := plans.ReplaceDraft(ctx, tenantA, plan.ID, "", draftDays(exercise.ID, "A", "B")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := plans.PublishDraft(ctx, tenantA, plan.ID, coach); err != nil {
		t.Fatal(err)
	}

	if _, err := plans.DuplicatePlan(ctx, repo.DuplicateParams{TenantID: tenantB, SourcePlanID: plan.ID, StudentID: student, CoachID: coach}); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não duplica plano de A: %v", err)
	}
	if _, err := plans.ArchivePlan(ctx, tenantB, plan.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não arquiva plano de A: %v", err)
	}
	if _, err := plans.ActivatePlan(ctx, tenantB, student, plan.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não ativa plano de A: %v", err)
	}
	if v, err := plans.ListVersionSummaries(ctx, tenantB, plan.ID); err != nil || len(v) != 0 {
		t.Fatalf("tenant B não lê versões de A: %v %+v", err, v)
	}

	// No tenant certo: o resumo traz autor e contagens.
	v, err := plans.ListVersionSummaries(ctx, tenantA, plan.ID)
	if err != nil || len(v) != 1 || v[0].PublishedBy != coach || v[0].DaysCount != 2 || v[0].ExercisesCount != 2 {
		t.Fatalf("resumo de versões: %v %+v", err, v)
	}
	// O ativo não arquiva.
	if _, err := plans.ArchivePlan(ctx, tenantA, plan.ID); !errors.Is(err, repo.ErrPlanIsActive) {
		t.Fatalf("arquivar o ativo: %v", err)
	}
}
