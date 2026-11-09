package repo_test

import (
	"context"
	"testing"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// TestStudentRepoTenantIsolationAndErasure: status e histórico de um tenant
// são invisíveis e intocáveis pelo outro (ADR-001 §6); a anonimização apaga o
// histórico (o motivo é texto livre) e o cadastro opcional.
func TestStudentRepoTenantIsolationAndErasure(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	users := repo.NewUserRepo(pool)
	students := repo.NewStudentRepo(pool)

	tenantA, ownerA := newTenantWithOwner(t, pool, "stu-a")
	tenantB, ownerB := newTenantWithOwner(t, pool, "stu-b")

	student, err := users.CreateStudent(ctx, domain.User{
		TenantID: tenantA, Email: "aluno@stu-a.com", PasswordHash: "h", Name: "Aluno A",
		Locale: "pt-BR", Status: domain.UserStatusActive, Roles: []domain.Role{domain.RoleStudent},
	}, ownerA)
	if err != nil {
		t.Fatalf("criar aluno: %v", err)
	}

	if err := students.SetStatus(ctx, tenantB, student.ID, domain.UserStatusInactive, ownerB, ""); err != repo.ErrNotFound {
		t.Fatalf("SetStatus cross-tenant: %v", err)
	}
	if _, err := students.Get(ctx, tenantB, student.ID); err != repo.ErrNotFound {
		t.Fatalf("Get cross-tenant: %v", err)
	}
	if _, err := students.StatusOf(ctx, tenantB, student.ID); err != repo.ErrNotFound {
		t.Fatalf("StatusOf cross-tenant: %v", err)
	}

	phone, birth := "11 99999-0000", "1990-01-02"
	if err := users.UpdateProfile(ctx, tenantA, student.ID, repo.ProfilePatch{Phone: &phone, BirthDate: &birth}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}
	if err := users.UpdateProfile(ctx, tenantB, student.ID, repo.ProfilePatch{Phone: &phone}); err != repo.ErrNotFound {
		t.Fatalf("UpdateProfile cross-tenant: %v", err)
	}

	if err := students.SetStatus(ctx, tenantA, student.ID, domain.UserStatusInactive, ownerA, "motivo livre"); err != nil {
		t.Fatalf("inativar: %v", err)
	}
	if err := students.SetStatus(ctx, tenantA, student.ID, domain.UserStatusInactive, ownerA, ""); err != repo.ErrAlreadyInStatus {
		t.Fatalf("inativar de novo: %v", err)
	}
	if events, _ := students.StatusHistory(ctx, tenantB, student.ID); len(events) != 0 {
		t.Fatalf("tenant B vê o histórico de A: %v", events)
	}
	if events, _ := students.StatusHistory(ctx, tenantA, student.ID); len(events) != 1 {
		t.Fatalf("histórico de A: %v", events)
	}

	// Exclusão: marca deleting (só `active`/`deleting` migram) e anonimiza.
	if err := students.SetStatus(ctx, tenantA, student.ID, domain.UserStatusActive, ownerA, ""); err != nil {
		t.Fatalf("reativar: %v", err)
	}
	if err := users.MarkDeleting(ctx, tenantA, student.ID); err != nil {
		t.Fatalf("MarkDeleting: %v", err)
	}
	if err := users.Anonymize(ctx, tenantA, student.ID); err != nil {
		t.Fatalf("Anonymize: %v", err)
	}
	if events, _ := students.StatusHistory(ctx, tenantA, student.ID); len(events) != 0 {
		t.Fatalf("histórico deveria sair com a exclusão: %v", events)
	}
}
