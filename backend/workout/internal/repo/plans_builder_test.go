package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// draftDays monta uma árvore mínima porém completa (dia → bloco → exercício →
// set) para os testes do builder.
func draftDays(exerciseID string, labels ...string) []domain.Day {
	days := make([]domain.Day, 0, len(labels))
	for _, label := range labels {
		days = append(days, domain.Day{
			Label: label, Title: "Treino " + label,
			Blocks: []domain.Block{{
				BlockType: domain.BlockTypeStraight, RestSeconds: 90,
				Exercises: []domain.BlockExercise{{
					ExerciseID: exerciseID, Notes: "cadência controlada",
					Sets: []domain.PrescribedSet{
						{RepsMin: intPtr(8), RepsMax: intPtr(12), TargetLoadKg: floatPtr(40), RestSeconds: intPtr(60)},
						{RepsMin: intPtr(8), RepsMax: intPtr(10), TargetLoadKg: floatPtr(45), RestSeconds: intPtr(60)},
					},
				}},
			}},
		})
	}
	return days
}

func newPlan(t *testing.T, plans *repo.PlanRepo, tenantID, studentID, coachID string) domain.Plan {
	t.Helper()
	plan, err := plans.CreatePlan(context.Background(), domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: coachID, Title: "Hipertrofia A/B",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	return plan
}

// TestPublishThenEditCreatesV2 é o Aceite do P1.4 no nível do repositório:
// publicar congela a v1 e uma edição posterior abre a v2 sem tocar nela
// (ADR-004 §1).
func TestPublishThenEditCreatesV2(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newTenant(), uuid.NewString()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantID)
	plan := newPlan(t, plans, tenantID, studentID, uuid.NewString())

	v1, days, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", draftDays(exercise.ID, "A", "B"))
	if err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	if v1.VersionNo != 1 || len(days) != 2 {
		t.Fatalf("esperava v1 com 2 dias, veio v%d com %d", v1.VersionNo, len(days))
	}

	published, state, err := plans.PublishDraft(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("publicar: %v", err)
	}
	if published.PublishedAt == nil || published.VersionNo != 1 {
		t.Fatalf("v1 deveria sair publicada, veio %+v", published)
	}
	if state.ActiveVersionID != v1.ID {
		t.Fatalf("estado deveria apontar para a v1, veio %q", state.ActiveVersionID)
	}
	// Primeiro publish: rotação começa no primeiro dia (ADR-004 §3).
	if state.NextDayID == nil || *state.NextDayID != days[0].ID {
		t.Fatalf("next_day_id deveria ser o dia A, veio %v", state.NextDayID)
	}

	// Editar depois de publicado abre a v2; a v1 continua com a carga antiga.
	edited := draftDays(exercise.ID, "A", "B", "C")
	edited[0].Blocks[0].Exercises[0].Sets[0].TargetLoadKg = floatPtr(50)
	v2, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "Hipertrofia A/B/C", edited)
	if err != nil {
		t.Fatalf("editar rascunho: %v", err)
	}
	if v2.VersionNo != 2 || v2.PublishedAt != nil {
		t.Fatalf("esperava v2 em rascunho, veio %+v", v2)
	}

	v1Tree, err := plans.GetVersionTree(ctx, tenantID, v1.ID)
	if err != nil {
		t.Fatalf("ler árvore da v1: %v", err)
	}
	if len(v1Tree) != 2 {
		t.Fatalf("v1 deveria continuar com 2 dias, veio %d", len(v1Tree))
	}
	if got := *v1Tree[0].Blocks[0].Exercises[0].Sets[0].TargetLoadKg; got != 40 {
		t.Fatalf("v1 deveria manter 40 kg, veio %v", got)
	}

	if _, _, err := plans.PublishDraft(ctx, tenantID, plan.ID); err != nil {
		t.Fatalf("publicar v2: %v", err)
	}
	updated, err := plans.GetPlan(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("reler plano: %v", err)
	}
	if updated.Title != "Hipertrofia A/B/C" || updated.Status != domain.PlanStatusPublished {
		t.Fatalf("plano deveria estar publicado com o título novo, veio %+v", updated)
	}
}

// TestPublishKeepsRotationLabel: republicar corrigindo uma carga não pode
// jogar quem estava no dia B de volta para o A (ADR-004 §3).
func TestPublishKeepsRotationLabel(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newTenant(), uuid.NewString()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantID)
	plan := newPlan(t, plans, tenantID, studentID, uuid.NewString())

	if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", draftDays(exercise.ID, "A", "B")); err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	if _, _, err := plans.PublishDraft(ctx, tenantID, plan.ID); err != nil {
		t.Fatalf("publicar v1: %v", err)
	}

	// O aluno terminou o A: a rotação está apontando para o B.
	tree, err := plans.GetVersionTree(ctx, tenantID, mustVersion(t, plans, tenantID, plan.ID).ID)
	if err != nil {
		t.Fatalf("ler árvore: %v", err)
	}
	dayB := tree[1].ID
	// O override manual da rotação ganha endpoint no P1.5; aqui o estado é
	// movido direto no banco, sob o mesmo escopo de RLS da aplicação.
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`UPDATE student_plan_state SET next_day_id = $1 WHERE student_id = $2`, dayB, studentID)
		return err
	}); err != nil {
		t.Fatalf("mover rotação para o B: %v", err)
	}

	if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", draftDays(exercise.ID, "A", "B")); err != nil {
		t.Fatalf("editar rascunho: %v", err)
	}
	_, state, err := plans.PublishDraft(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("publicar v2: %v", err)
	}
	newTree, err := plans.GetVersionTree(ctx, tenantID, state.ActiveVersionID)
	if err != nil {
		t.Fatalf("ler árvore da v2: %v", err)
	}
	if state.NextDayID == nil || *state.NextDayID != newTree[1].ID {
		t.Fatalf("rotação deveria seguir no dia B da v2, veio %v", state.NextDayID)
	}
}

// TestPublishRejectsIncomplete cobre as validações de publicação: sem dia,
// dia sem bloco, bloco sem exercício, exercício sem set — e publicar sem
// rascunho aberto.
func TestPublishRejectsIncomplete(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantID)

	dayWithoutBlock := []domain.Day{{Label: "A"}}
	blockWithoutExercise := []domain.Day{{Label: "A", Blocks: []domain.Block{{BlockType: domain.BlockTypeStraight}}}}
	exerciseWithoutSet := []domain.Day{{Label: "A", Blocks: []domain.Block{{
		BlockType: domain.BlockTypeStraight,
		Exercises: []domain.BlockExercise{{ExerciseID: exercise.ID}},
	}}}}

	cases := []struct {
		name   string
		days   []domain.Day
		reason string
	}{
		{"sem dias", nil, "no_days"},
		{"dia sem bloco", dayWithoutBlock, "day_without_block"},
		{"bloco sem exercício", blockWithoutExercise, "block_without_exercise"},
		{"exercício sem set", exerciseWithoutSet, "exercise_without_set"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			plan := newPlan(t, plans, tenantID, uuid.NewString(), uuid.NewString())
			if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", tc.days); err != nil {
				t.Fatalf("gravar rascunho: %v", err)
			}
			_, _, err := plans.PublishDraft(ctx, tenantID, plan.ID)
			var incomplete repo.IncompletePlanError
			if !errors.As(err, &incomplete) {
				t.Fatalf("esperava plano incompleto, veio %v", err)
			}
			if incomplete.Reason != tc.reason {
				t.Fatalf("esperava reason %q, veio %q", tc.reason, incomplete.Reason)
			}
		})
	}

	t.Run("sem rascunho", func(t *testing.T) {
		plan := newPlan(t, plans, tenantID, uuid.NewString(), uuid.NewString())
		if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", draftDays(exercise.ID, "A")); err != nil {
			t.Fatalf("gravar rascunho: %v", err)
		}
		if _, _, err := plans.PublishDraft(ctx, tenantID, plan.ID); err != nil {
			t.Fatalf("publicar: %v", err)
		}
		if _, _, err := plans.PublishDraft(ctx, tenantID, plan.ID); !errors.Is(err, repo.ErrNoDraft) {
			t.Fatalf("esperava ErrNoDraft ao publicar duas vezes, veio %v", err)
		}
	})
}

// TestDraftRejectsForeignExercise: a FK de block_exercises não enxerga RLS, e
// sem a checagem explícita um UUID de exercício de outro tenant entraria no
// plano.
func TestDraftRejectsForeignExercise(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	plans := repo.NewPlanRepo(pool)
	foreign := seedExercise(t, pool, tenantB)
	plan := newPlan(t, plans, tenantA, uuid.NewString(), uuid.NewString())

	_, _, err := plans.ReplaceDraft(ctx, tenantA, plan.ID, "", draftDays(foreign.ID, "A"))
	var unknown repo.UnknownExerciseError
	if !errors.As(err, &unknown) {
		t.Fatalf("esperava UnknownExerciseError, veio %v", err)
	}
	if unknown.ExerciseID != foreign.ID {
		t.Fatalf("erro deveria apontar o exercício recusado, veio %q", unknown.ExerciseID)
	}
}

// TestPlanIsolationBetweenTenants: plano do tenant A é invisível para o B,
// nas duas direções (ADR-001).
func TestPlanIsolationBetweenTenants(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantA)
	studentID := uuid.NewString()
	plan := newPlan(t, plans, tenantA, studentID, uuid.NewString())
	if _, _, err := plans.ReplaceDraft(ctx, tenantA, plan.ID, "", draftDays(exercise.ID, "A")); err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	if _, _, err := plans.PublishDraft(ctx, tenantA, plan.ID); err != nil {
		t.Fatalf("publicar: %v", err)
	}

	if _, err := plans.GetPlan(ctx, tenantB, plan.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não deveria ler o plano do A, veio %v", err)
	}
	if _, err := plans.GetState(ctx, tenantB, studentID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("tenant B não deveria ler o estado do aluno do A, veio %v", err)
	}
	list, err := plans.ListPlansByStudent(ctx, tenantB, studentID)
	if err != nil {
		t.Fatalf("listar planos: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("tenant B deveria ver lista vazia, veio %d planos", len(list))
	}

	summaries, err := plans.ListPlansByStudent(ctx, tenantA, studentID)
	if err != nil {
		t.Fatalf("listar planos do A: %v", err)
	}
	if len(summaries) != 1 || !summaries[0].IsActive || summaries[0].PublishedVersionNo != 1 {
		t.Fatalf("resumo do plano do A veio errado: %+v", summaries)
	}
}

func mustVersion(t *testing.T, plans *repo.PlanRepo, tenantID, planID string) domain.PlanVersion {
	t.Helper()
	v, err := plans.LatestVersion(context.Background(), tenantID, planID)
	if err != nil {
		t.Fatalf("buscar versão: %v", err)
	}
	return v
}

// TestVersionTreeWithSiblings é regressão do bug achado no smoke do P1.4: a
// remontagem da árvore guardava ponteiro para elemento de slice, e o `append`
// do irmão seguinte realocava o array — os sets do primeiro exercício de um
// bloco com dois exercícios sumiam da leitura.
func TestVersionTreeWithSiblings(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)
	first := seedExercise(t, pool, tenantID)
	second := seedExercise(t, pool, tenantID)
	plan := newPlan(t, plans, tenantID, uuid.NewString(), uuid.NewString())

	set := func(reps int) domain.PrescribedSet {
		return domain.PrescribedSet{RepsMin: intPtr(reps), RepsMax: intPtr(reps), RestSeconds: intPtr(60)}
	}
	days := []domain.Day{{
		Label: "A",
		Blocks: []domain.Block{
			{BlockType: domain.BlockTypeSuperset, Exercises: []domain.BlockExercise{
				{ExerciseID: first.ID, Sets: []domain.PrescribedSet{set(8), set(10)}},
				{ExerciseID: second.ID, Sets: []domain.PrescribedSet{set(12)}},
			}},
			{BlockType: domain.BlockTypeStraight, Exercises: []domain.BlockExercise{
				{ExerciseID: second.ID, Sets: []domain.PrescribedSet{set(15), set(15), set(15)}},
			}},
		},
	}}

	version, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", days)
	if err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	tree, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		t.Fatalf("ler árvore: %v", err)
	}

	want := [][]int{{2, 1}, {3}}
	if len(tree) != 1 || len(tree[0].Blocks) != len(want) {
		t.Fatalf("esperava 1 dia com %d blocos, veio %d dias", len(want), len(tree))
	}
	for bi, blockWant := range want {
		block := tree[0].Blocks[bi]
		if len(block.Exercises) != len(blockWant) {
			t.Fatalf("bloco %d: esperava %d exercícios, veio %d", bi, len(blockWant), len(block.Exercises))
		}
		for ei, sets := range blockWant {
			if got := len(block.Exercises[ei].Sets); got != sets {
				t.Fatalf("bloco %d, exercício %d: esperava %d sets, veio %d", bi, ei, sets, got)
			}
		}
	}
}
