package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

func ptr[T any](v T) *T { return &v }

// TestProfileAndInjuryTenantIsolation: o mesmo UUID de aluno em outro tenant
// não enxerga nem altera a anamnese (RLS, ADR-001 §6); coach_notes só é
// escrita quando pedido.
func TestProfileAndInjuryTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	profiles, injuries := repo.NewProfileRepo(pool), repo.NewInjuryRepo(pool)
	tenantA, tenantB, student, actor := newID(), newID(), newID(), newID()

	if _, err := profiles.Upsert(ctx, domain.StudentProfile{
		TenantID: tenantA, StudentID: student, Goal: ptr("health"), WeeklyTarget: ptr(3),
		CoachNotes: "nota", UpdatedBy: actor,
	}, true); err != nil {
		t.Fatalf("upsert coach: %v", err)
	}
	// Upsert do aluno preserva a nota e a meta semanal do coach.
	saved, err := profiles.Upsert(ctx, domain.StudentProfile{
		TenantID: tenantA, StudentID: student, Goal: ptr("strength"), UpdatedBy: student,
	}, false)
	if err != nil {
		t.Fatalf("upsert aluno: %v", err)
	}
	if saved.CoachNotes != "nota" || *saved.Goal != "strength" || saved.WeeklyTarget == nil || *saved.WeeklyTarget != 3 {
		t.Fatalf("upsert do aluno errado: %+v", saved)
	}

	inj, err := injuries.Create(ctx, domain.StudentInjury{
		TenantID: tenantA, StudentID: student, BodyRegion: "knee", Description: "x", CreatedBy: actor,
	})
	if err != nil {
		t.Fatalf("criar lesão: %v", err)
	}

	if _, err := profiles.Get(ctx, tenantB, student); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("outro tenant não pode ler o perfil: %v", err)
	}
	if list, _ := injuries.List(ctx, tenantB, student, false); len(list) != 0 {
		t.Fatalf("outro tenant não pode listar lesões: %+v", list)
	}
	if err := injuries.Delete(ctx, tenantB, student, inj.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("outro tenant não pode apagar: %v", err)
	}
	_, err = injuries.Update(ctx, tenantB, student, inj.ID, func(*domain.StudentInjury) error { return nil })
	if !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("outro tenant não pode atualizar: %v", err)
	}
	if list, _ := injuries.List(ctx, tenantA, student, false); len(list) != 1 {
		t.Fatalf("a lesão do tenant A deveria seguir intacta: %+v", list)
	}
}
