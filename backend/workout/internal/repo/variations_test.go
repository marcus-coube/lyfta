package repo_test

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// A variação de um tenant não existe para outro: nem na lista, nem no
// update/arquivar (RLS) — e a árvore de outro tenant não a referencia.
func TestVariationsAreTenantIsolated(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	variations := repo.NewVariationRepo(pool)

	v, err := variations.Create(ctx, tenantA, uuid.NewString(), "Pausa no fundo", "desc")
	if err != nil {
		t.Fatalf("criar: %v", err)
	}
	if items, err := variations.List(ctx, tenantB, "", "all"); err != nil || len(items) != 0 {
		t.Fatalf("tenant B não deveria listar: %v %+v", err, items)
	}
	if _, err := variations.Update(ctx, tenantB, v.ID, "invasão", ""); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("update cross-tenant deveria ser ErrNotFound, veio %v", err)
	}
	if _, err := variations.SetArchived(ctx, tenantB, v.ID, true); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("arquivar cross-tenant deveria ser ErrNotFound, veio %v", err)
	}
	// O mesmo nome em outro tenant não conflita.
	if _, err := variations.Create(ctx, tenantB, uuid.NewString(), "Pausa no fundo", ""); err != nil {
		t.Fatalf("mesmo nome em outro tenant deveria passar: %v", err)
	}
	if _, err := variations.Create(ctx, tenantA, uuid.NewString(), "PAUSA no fundo", ""); !errors.Is(err, repo.ErrVariationNameTaken) {
		t.Fatalf("nome repetido no tenant deveria ser ErrVariationNameTaken, veio %v", err)
	}

	// Plano do tenant B referenciando variação do A: recusado.
	exercise := seedExercise(t, pool, tenantB)
	plans := repo.NewPlanRepo(pool)
	plan := newPlan(t, plans, tenantB, uuid.NewString(), uuid.NewString())
	days := draftDays(exercise.ID, "A")
	days[0].Blocks[0].Exercises[0].Sets[0].VariationID = &v.ID
	_, _, err = plans.ReplaceDraft(ctx, tenantB, plan.ID, "", days)
	var unknown repo.UnknownVariationError
	if !errors.As(err, &unknown) || unknown.VariationID != v.ID {
		t.Fatalf("variação de outro tenant deveria ser UnknownVariationError, veio %v", err)
	}
}

// Editar o nome da variação muda a leitura viva (plano/Hoje), mas não o
// snapshot de uma sessão já iniciada (ADR-004 §2); o snapshot novo traz o
// nome atual. Cópia de árvore carrega variation_id.
func TestVariationSnapshotIsFrozen(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newTenant(), uuid.NewString()
	plans := repo.NewPlanRepo(pool)
	sessions := repo.NewSessionRepo(pool)
	variations := repo.NewVariationRepo(pool)
	exercise := seedExercise(t, pool, tenantID)
	plan := newPlan(t, plans, tenantID, studentID, uuid.NewString())

	v, err := variations.Create(ctx, tenantID, uuid.NewString(), "Pausa no fundo", "Segure 2 s.")
	if err != nil {
		t.Fatalf("criar variação: %v", err)
	}
	days := draftDays(exercise.ID, "A")
	days[0].Blocks[0].Exercises[0].Sets[1].VariationID = &v.ID
	if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", days); err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	version, _, err := plans.PublishDraft(ctx, tenantID, plan.ID, "")
	if err != nil {
		t.Fatalf("publicar: %v", err)
	}
	tree, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		t.Fatalf("ler árvore: %v", err)
	}
	sets := tree[0].Blocks[0].Exercises[0].Sets
	if sets[0].Variation != nil || sets[1].Variation == nil || sets[1].Variation.Name != "Pausa no fundo" {
		t.Fatalf("árvore sem variação: %+v", sets)
	}

	start := func() string {
		res, err := sessions.ApplyEvents(ctx, tenantID, studentID, []domain.SyncEvent{{
			ClientID: uuid.NewString(), Type: domain.SyncEventSessionStart,
			PerformedAt: time.Now(), DayID: tree[0].ID,
		}})
		if err != nil || res[0].Status != domain.SyncStatusAccepted {
			t.Fatalf("iniciar sessão: %v %+v", err, res)
		}
		return res[0].SessionID
	}
	snapName := func(sessionID string) (name, desc string, hasFirst bool) {
		raw, err := sessions.SessionSnapshot(ctx, tenantID, studentID, sessionID)
		if err != nil {
			t.Fatalf("ler snapshot: %v", err)
		}
		var snap struct {
			Blocks []struct {
				Exercises []struct {
					Sets []struct {
						Variation *struct {
							Name        string `json:"name"`
							Description string `json:"description"`
						} `json:"variation"`
					} `json:"sets"`
				} `json:"exercises"`
			} `json:"blocks"`
		}
		if err := json.Unmarshal(raw, &snap); err != nil {
			t.Fatalf("decodificar snapshot: %v (%s)", err, raw)
		}
		s := snap.Blocks[0].Exercises[0].Sets
		if s[1].Variation == nil {
			t.Fatalf("snapshot sem variação: %s", raw)
		}
		return s[1].Variation.Name, s[1].Variation.Description, s[0].Variation != nil
	}

	first := start()
	if name, desc, hasFirst := snapName(first); name != "Pausa no fundo" || desc != "Segure 2 s." || hasFirst {
		t.Fatalf("snapshot inicial inesperado: %q %q %v", name, desc, hasFirst)
	}

	if _, err := variations.Update(ctx, tenantID, v.ID, "Pausa 3 s", "Segure 3 s."); err != nil {
		t.Fatalf("renomear: %v", err)
	}
	if name, desc, _ := snapName(first); name != "Pausa no fundo" || desc != "Segure 2 s." {
		t.Fatalf("snapshot da sessão iniciada não pode mudar: %q %q", name, desc)
	}
	live, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil || live[0].Blocks[0].Exercises[0].Sets[1].Variation.Name != "Pausa 3 s" {
		t.Fatalf("leitura viva deveria mostrar o nome novo: %v", err)
	}
	if name, _, _ := snapName(start()); name != "Pausa 3 s" {
		t.Fatalf("snapshot de sessão nova deveria trazer o nome atual, veio %q", name)
	}

	// Duplicar carrega variation_id (cópia de árvore, mesmo tenant).
	dup, err := plans.DuplicatePlan(ctx, repo.DuplicateParams{
		TenantID: tenantID, SourcePlanID: plan.ID, StudentID: studentID, CoachID: uuid.NewString(),
	})
	if err != nil {
		t.Fatalf("duplicar: %v", err)
	}
	dv, err := plans.LatestVersion(ctx, tenantID, dup.ID)
	if err != nil {
		t.Fatalf("versão da cópia: %v", err)
	}
	dtree, err := plans.GetVersionTree(ctx, tenantID, dv.ID)
	if err != nil || dtree[0].Blocks[0].Exercises[0].Sets[1].VariationID == nil ||
		*dtree[0].Blocks[0].Exercises[0].Sets[1].VariationID != v.ID {
		t.Fatalf("cópia deveria carregar variation_id: %v %+v", err, dtree)
	}
}
