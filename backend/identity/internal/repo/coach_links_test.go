package repo_test

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

func newTenantWithOwner(t *testing.T, pool *pgxpool.Pool, label string) (tenantID, ownerID string) {
	t.Helper()
	ctx := context.Background()
	tenant, err := repo.NewTenantRepo(pool).Create(ctx, domain.Tenant{Name: label, Slug: uniqueSlug(label), Locale: "pt-BR"})
	if err != nil {
		t.Fatalf("criar tenant: %v", err)
	}
	owner, err := repo.NewUserRepo(pool).Create(ctx, domain.User{
		TenantID: tenant.ID, Email: label + "-owner@x.com", PasswordHash: "h", Name: "Owner " + label,
		Locale: "pt-BR", Status: domain.UserStatusActive,
		Roles: []domain.Role{domain.RoleOwner, domain.RoleCoach},
	})
	if err != nil {
		t.Fatalf("criar owner: %v", err)
	}
	return tenant.ID, owner.ID
}

// TestCoachLinkTenantIsolation: o vínculo de um tenant é invisível e
// intocável pelo outro (ADR-001 §6).
func TestCoachLinkTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	users := repo.NewUserRepo(pool)
	links := repo.NewCoachLinkRepo(pool)

	tenantA, ownerA := newTenantWithOwner(t, pool, "iso-a")
	tenantB, ownerB := newTenantWithOwner(t, pool, "iso-b")

	student, err := users.CreateStudent(ctx, domain.User{
		TenantID: tenantA, Email: "aluno@iso-a.com", PasswordHash: "", Name: "Aluno A",
		Locale: "pt-BR", Status: domain.UserStatusInvited, Roles: []domain.Role{domain.RoleStudent},
	}, ownerA)
	if err != nil {
		t.Fatalf("criar aluno vinculado: %v", err)
	}

	ids, err := links.StudentIDs(ctx, tenantA, ownerA)
	if err != nil || len(ids) != 1 || ids[0] != student.ID {
		t.Fatalf("StudentIDs no tenant A: %v %v", ids, err)
	}
	// Tenant B não enxerga o vínculo, nem o coach do aluno de A.
	if ids, _ := links.StudentIDs(ctx, tenantB, ownerA); len(ids) != 0 {
		t.Fatalf("tenant B vê alunos de A: %v", ids)
	}
	if _, err := links.CoachOf(ctx, tenantB, student.ID); err != repo.ErrNotFound {
		t.Fatalf("CoachOf cross-tenant: %v", err)
	}
	// Reatribuir pelo tenant B falha (aluno inexistente para ele).
	if err := links.Reassign(ctx, tenantB, student.ID, ownerB, ownerB); err != repo.ErrInvalidLink {
		t.Fatalf("Reassign cross-tenant: %v", err)
	}
	if got, _ := links.CoachOf(ctx, tenantA, student.ID); got != ownerA {
		t.Fatalf("vínculo de A foi alterado: %s", got)
	}
}

// TestBackfillCoachLinks roda o backfill da migration 0012 como superusuário
// (a role da aplicação não rodaria: sem tenant setado o RLS esconde tudo) e
// confere as duas regras: o convidador ativo coach|owner vence; senão, o
// owner ativo mais antigo.
func TestBackfillCoachLinks(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()

	dsn := os.Getenv("SUPERUSER_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres@localhost:5432/lyfta_identity?sslmode=disable"
	}
	super, err := repo.NewPool(ctx, dsn)
	if err != nil {
		if os.Getenv("CI") != "" {
			t.Fatalf("superusuário indisponível no CI: %v", err)
		}
		t.Skipf("superusuário indisponível: %v", err)
	}
	defer super.Close()

	sqlBytes, err := os.ReadFile("../../migrations/0012_coach_students.up.sql")
	if err != nil {
		t.Fatalf("ler migration: %v", err)
	}
	full := string(sqlBytes)
	idx := strings.Index(full, "INSERT INTO coach_students (tenant_id, student_id, coach_id)\nSELECT tenant_id")
	if idx < 0 {
		t.Fatal("backfill não encontrado na migration 0012")
	}
	backfill := full[idx:]

	users := repo.NewUserRepo(pool)
	invitations := repo.NewInvitationRepo(pool)
	tenantID, ownerID := newTenantWithOwner(t, pool, "backfill")
	coach, err := users.Create(ctx, domain.User{
		TenantID: tenantID, Email: "coach@backfill.com", PasswordHash: "h", Name: "Coach",
		Locale: "pt-BR", Status: domain.UserStatusActive, Roles: []domain.Role{domain.RoleCoach},
	})
	if err != nil {
		t.Fatalf("criar coach: %v", err)
	}
	gone, err := users.Create(ctx, domain.User{
		TenantID: tenantID, Email: "gone@backfill.com", PasswordHash: "h", Name: "Gone",
		Locale: "pt-BR", Status: domain.UserStatusActive, Roles: []domain.Role{domain.RoleCoach},
	})
	if err != nil {
		t.Fatalf("criar coach 2: %v", err)
	}

	mkStudent := func(email, invitedBy string) string {
		u, err := users.Create(ctx, domain.User{
			TenantID: tenantID, Email: email, PasswordHash: "", Name: email,
			Locale: "pt-BR", Status: domain.UserStatusActive, Roles: []domain.Role{domain.RoleStudent},
		})
		if err != nil {
			t.Fatalf("criar aluno: %v", err)
		}
		if invitedBy != "" {
			if _, err := invitations.Create(ctx, domain.Invitation{
				TenantID: tenantID, Email: email, Role: domain.RoleStudent,
				TokenHash: "hash-" + u.ID, InvitedBy: invitedBy, ExpiresAt: u.CreatedAt.AddDate(0, 0, 7),
			}); err != nil {
				t.Fatalf("criar convite: %v", err)
			}
		}
		return u.ID
	}
	byCoach := mkStudent("a@backfill.com", coach.ID)
	byGone := mkStudent("b@backfill.com", gone.ID)
	noInvite := mkStudent("c@backfill.com", "")

	// `gone` deixou de ser ativo: o convite dele não vale mais.
	if _, err := super.Exec(ctx, `UPDATE users SET status = 'disabled' WHERE id = $1`, gone.ID); err != nil {
		t.Fatalf("desativar coach: %v", err)
	}
	if _, err := super.Exec(ctx, backfill); err != nil {
		t.Fatalf("rodar backfill: %v", err)
	}

	links := repo.NewCoachLinkRepo(pool)
	for name, want := range map[string][2]string{
		"convidado por coach ativo":  {byCoach, coach.ID},
		"convidador inativo":         {byGone, ownerID},
		"sem convite (cai no owner)": {noInvite, ownerID},
	} {
		got, err := links.CoachOf(ctx, tenantID, want[0])
		if err != nil || got != want[1] {
			t.Errorf("%s: coach=%q err=%v, esperava %q", name, got, err, want[1])
		}
	}

	// Idempotente: rodar de novo não duplica nem troca nada.
	if _, err := super.Exec(ctx, backfill); err != nil {
		t.Fatalf("backfill repetido: %v", err)
	}
	if got, _ := links.CoachOf(ctx, tenantID, byCoach); got != coach.ID {
		t.Errorf("backfill repetido mudou o vínculo: %q", got)
	}
}
