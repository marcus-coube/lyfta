package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

func publishedTemplate(t *testing.T, plans *repo.PlanRepo, tenantID, coachID, exerciseID string) domain.Plan {
	t.Helper()
	ctx := context.Background()
	tpl, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, CoachID: coachID, Title: "Modelo", Kind: domain.PlanKindTemplate,
	})
	if err != nil {
		t.Fatalf("criar modelo: %v", err)
	}
	if _, _, err := plans.ReplaceDraft(ctx, tenantID, tpl.ID, "", draftDays(exerciseID, "A", "B")); err != nil {
		t.Fatalf("salvar modelo: %v", err)
	}
	if _, state, err := plans.PublishDraft(ctx, tenantID, tpl.ID, ""); err != nil || state.PlanID != "" {
		t.Fatalf("publicar modelo (sem rotação): %v %+v", err, state)
	}
	return tpl
}

// Modelo é do tenant: outro tenant não lista, não lê, não arquiva nem copia.
func TestTemplatesAreTenantIsolated(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantA)
	tpl := publishedTemplate(t, plans, tenantA, uuid.NewString(), exercise.ID)

	items, _, err := plans.ListTemplates(ctx, tenantA, repo.TemplateFilter{})
	if err != nil || len(items) != 1 || items[0].DaysCount != 2 || items[0].ExercisesCount != 2 {
		t.Fatalf("tenant A deveria listar o modelo com contagens: %v %+v", err, items)
	}
	if items, _, err := plans.ListTemplates(ctx, tenantB, repo.TemplateFilter{}); err != nil || len(items) != 0 {
		t.Fatalf("tenant B não pode listar modelo de A: %v %+v", err, items)
	}
	if _, err := plans.GetPlan(ctx, tenantB, tpl.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não lê o modelo: %v", err)
	}
	if _, err := plans.LatestPublishedVersion(ctx, tenantB, tpl.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não lê versões do modelo: %v", err)
	}
	if err := plans.ArchiveTemplate(ctx, tenantB, tpl.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não arquiva o modelo: %v", err)
	}
	if recipients, err := plans.ListRecipients(ctx, tenantB, tpl.ID); err != nil || len(recipients) != 0 {
		t.Fatalf("tenant B não vê destinatários: %v %+v", err, recipients)
	}
}

// A atribuição é uma transação por aluno: se a cópia falha no meio, não sobra
// plano pela metade; e o banco recusa plano de aluno sem aluno.
func TestAssignRollsBackAndSchemaGuardsKind(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantID)
	tpl := publishedTemplate(t, plans, tenantID, uuid.NewString(), exercise.ID)
	version, err := plans.LatestPublishedVersion(ctx, tenantID, tpl.ID)
	if err != nil {
		t.Fatalf("versão publicada: %v", err)
	}
	days, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		t.Fatalf("árvore: %v", err)
	}

	// Exercício que o tenant não enxerga na árvore: a transação inteira cai.
	broken := append([]domain.Day(nil), days...)
	broken[1].Blocks = []domain.Block{{Exercises: []domain.BlockExercise{{ExerciseID: uuid.NewString()}}}}
	student := uuid.NewString()
	_, err = plans.AssignTemplate(ctx, repo.AssignParams{
		TenantID: tenantID, CoachID: uuid.NewString(), StudentID: student,
		Template: tpl, TemplateVersion: version, Days: broken, Publish: true,
	})
	var unknown repo.UnknownExerciseError
	if !errors.As(err, &unknown) {
		t.Fatalf("esperava UnknownExerciseError, veio %v", err)
	}
	if got, err := plans.ListPlansByStudent(ctx, tenantID, student); err != nil || len(got) != 0 {
		t.Fatalf("falha na cópia não pode deixar plano para trás: %v %+v", err, got)
	}

	// CHECK (kind='assigned') = (student_id IS NOT NULL).
	if _, err := plans.CreatePlan(ctx, domain.Plan{TenantID: tenantID, CoachID: uuid.NewString(), Title: "Sem aluno"}); err == nil {
		t.Fatal("plano atribuído sem aluno deveria ser recusado pelo CHECK")
	}
	if _, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, CoachID: uuid.NewString(), Title: "Modelo com aluno",
		StudentID: uuid.NewString(), Kind: domain.PlanKindTemplate,
	}); err == nil {
		t.Fatal("modelo com aluno deveria ser recusado pelo CHECK")
	}
}
