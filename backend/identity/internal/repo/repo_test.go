package repo_test

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// testPool abre um pool contra o Postgres de dev (lyfta_identity, migrations
// já aplicadas). Sem DATABASE_URL configurada explicitamente, usa o mesmo
// default documentado em backend/identity/.env.example. Fora do CI, pula o
// teste se o banco não estiver acessível — mantém `go test ./...` rodável
// sem Postgres.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		// lyfta_app: role sem BYPASSRLS (migration 0002_app_role) — RLS não
		// tem efeito nenhum se o teste conectar como superusuário (postgres).
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_identity?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		// No CI (P0.7) o Postgres é service container obrigatório: pular aqui
		// deixaria o pipeline verde sem ter testado nada.
		if os.Getenv("CI") != "" {
			t.Fatalf("banco indisponível no CI: %v", err)
		}
		t.Skipf("banco indisponível para teste de integração: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// TestTenantAndUserIsolation cobre o Aceite de P0.2: criar tenant+user
// respeitando RLS, e confirmar que um tenant nunca enxerga usuários de
// outro tenant (ADR-001 §6: teste de isolamento cross-tenant obrigatório).
func TestTenantAndUserIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()

	tenants := repo.NewTenantRepo(pool)
	users := repo.NewUserRepo(pool)

	tenantA, err := tenants.Create(ctx, domain.Tenant{
		Name: "Academia A", Slug: uniqueSlug("academia-a"), Locale: "pt-BR",
	})
	if err != nil {
		t.Fatalf("criar tenant A: %v", err)
	}
	tenantB, err := tenants.Create(ctx, domain.Tenant{
		Name: "Academia B", Slug: uniqueSlug("academia-b"), Locale: "pt-BR",
	})
	if err != nil {
		t.Fatalf("criar tenant B: %v", err)
	}

	userA, err := users.Create(ctx, domain.User{
		TenantID: tenantA.ID, Email: "owner@a.com", PasswordHash: "hash",
		Name: "Owner A", Locale: "pt-BR", Status: domain.UserStatusActive,
		Roles: []domain.Role{domain.RoleOwner, domain.RoleCoach},
	})
	if err != nil {
		t.Fatalf("criar user A: %v", err)
	}
	if userA.ID == "" {
		t.Fatal("esperava id gerado para o usuário A")
	}

	if _, err := users.Create(ctx, domain.User{
		TenantID: tenantB.ID, Email: "owner@b.com", PasswordHash: "hash",
		Name: "Owner B", Locale: "pt-BR", Status: domain.UserStatusActive,
		Roles: []domain.Role{domain.RoleOwner},
	}); err != nil {
		t.Fatalf("criar user B: %v", err)
	}

	// Isolamento: listar sob o tenant A não pode retornar o usuário do tenant B.
	usersInA, err := users.ListByTenant(ctx, tenantA.ID)
	if err != nil {
		t.Fatalf("listar usuários do tenant A: %v", err)
	}
	if len(usersInA) != 1 || usersInA[0].Email != "owner@a.com" {
		t.Fatalf("esperava só owner@a.com no tenant A, obtive: %+v", usersInA)
	}

	// Buscar o e-mail do tenant B usando o tenant A setado deve falhar (RLS).
	if _, err := users.FindByEmailInTenant(ctx, tenantA.ID, "owner@b.com"); err != repo.ErrNotFound {
		t.Fatalf("esperava ErrNotFound ao buscar user de outro tenant, obtive: %v", err)
	}

	// Buscar corretamente sob o próprio tenant funciona.
	found, err := users.FindByEmailInTenant(ctx, tenantA.ID, "owner@a.com")
	if err != nil {
		t.Fatalf("buscar user A pelo próprio tenant: %v", err)
	}
	if len(found.Roles) != 2 {
		t.Fatalf("esperava 2 papéis para user A, obtive: %+v", found.Roles)
	}
}

func uniqueSlug(prefix string) string {
	return prefix + "-" + uuid.NewString()[:8]
}

// TestCreateTenantWithOwnerTransactional cobre o Aceite de P0.3: signup cria
// tenant + user owner "numa transação" — se a inserção do usuário falhar, o
// tenant não deve ficar órfão no banco (rollback completo).
func TestCreateTenantWithOwnerTransactional(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenants := repo.NewTenantRepo(pool)

	t.Run("caminho feliz cria tenant e owner juntos", func(t *testing.T) {
		slug := uniqueSlug("signup-ok")
		tenant, user, err := tenants.CreateWithOwner(ctx,
			domain.Tenant{Name: "Academia Signup", Slug: slug, Locale: "pt-BR"},
			domain.User{
				Email: "owner@signup-ok.com", PasswordHash: "hash",
				Name: "Owner Signup", Locale: "pt-BR", Status: domain.UserStatusActive,
				Roles: []domain.Role{domain.RoleOwner, domain.RoleCoach},
			},
			"v1", []string{domain.PurposeTerms},
		)
		if err != nil {
			t.Fatalf("CreateWithOwner: %v", err)
		}
		if tenant.ID == "" || user.ID == "" {
			t.Fatalf("esperava ids gerados, obtive tenant=%+v user=%+v", tenant, user)
		}
		if user.TenantID != tenant.ID {
			t.Fatalf("esperava user.TenantID == tenant.ID, obtive %s != %s", user.TenantID, tenant.ID)
		}
	})

	t.Run("papel inválido reverte a criação do tenant (sem órfão)", func(t *testing.T) {
		slug := uniqueSlug("signup-fail")
		_, _, err := tenants.CreateWithOwner(ctx,
			domain.Tenant{Name: "Academia Falha", Slug: slug, Locale: "pt-BR"},
			domain.User{
				Email: "owner@signup-fail.com", PasswordHash: "hash",
				Name: "Owner Falha", Locale: "pt-BR", Status: domain.UserStatusActive,
				Roles: []domain.Role{"papel-invalido"}, // viola CHECK de user_roles.role
			},
			"v1", []string{domain.PurposeTerms},
		)
		if err == nil {
			t.Fatal("esperava erro ao inserir papel inválido")
		}

		if _, err := tenants.FindBySlug(ctx, slug); err != repo.ErrNotFound {
			t.Fatalf("esperava tenant revertido (ErrNotFound), obtive: %v", err)
		}
	})
}

// TestConsentsIsolationAndAppendOnly cobre o repositório de consentimentos
// (P4.5): isolamento cross-tenant (ADR-001 §6) e histórico append-only —
// revogar não apaga linha e conceder de novo cria outra.
func TestConsentsIsolationAndAppendOnly(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenants := repo.NewTenantRepo(pool)
	users := repo.NewUserRepo(pool)
	consents := repo.NewConsentRepo(pool)

	tenantA, _ := tenants.Create(ctx, domain.Tenant{Name: "Consent A", Slug: uniqueSlug("consent-a"), Locale: "pt-BR"})
	tenantB, _ := tenants.Create(ctx, domain.Tenant{Name: "Consent B", Slug: uniqueSlug("consent-b"), Locale: "pt-BR"})
	userA, err := users.Create(ctx, domain.User{
		TenantID: tenantA.ID, Email: "aluno@consent-a.com", PasswordHash: "hash", Name: "Aluno A",
		Locale: "pt-BR", Status: domain.UserStatusActive, Roles: []domain.Role{domain.RoleStudent},
	})
	if err != nil {
		t.Fatalf("criar usuário: %v", err)
	}

	if err := consents.Apply(ctx, tenantA.ID, userA.ID, "v1", map[string]bool{
		domain.PurposeTerms: true, domain.PurposeHealthData: true, domain.PurposeProgressPhotos: true,
	}); err != nil {
		t.Fatalf("conceder: %v", err)
	}
	// Idempotente: repetir na mesma versão não duplica a linha vigente.
	if err := consents.Apply(ctx, tenantA.ID, userA.ID, "v1", map[string]bool{domain.PurposeTerms: true}); err != nil {
		t.Fatalf("repetir: %v", err)
	}

	// Outro tenant não enxerga os consentimentos do usuário de A.
	other, err := consents.Active(ctx, tenantB.ID, userA.ID)
	if err != nil || len(other) != 0 {
		t.Fatalf("isolamento: tenant B não deveria ver consentimentos de A: %v %v", other, err)
	}

	// Revogar grava revoked_at, não apaga.
	if err := consents.Apply(ctx, tenantA.ID, userA.ID, "v1", map[string]bool{domain.PurposeProgressPhotos: false}); err != nil {
		t.Fatalf("revogar: %v", err)
	}
	purposes, _ := consents.ActivePurposes(ctx, tenantA.ID, userA.ID, "v1")
	if len(purposes) != 2 {
		t.Fatalf("esperava 2 finalidades vigentes após revogar, obtive %v", purposes)
	}
	var total int
	err = repo.WithTenant(ctx, pool, tenantA.ID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT count(*) FROM consents WHERE user_id = $1 AND purpose = 'progress_photos'`, userA.ID).Scan(&total)
	})
	if err != nil || total != 1 {
		t.Fatalf("a linha revogada deveria continuar no banco: total=%d err=%v", total, err)
	}

	// Conceder de novo cria outra linha; versão nova dos termos encerra a velha.
	if err := consents.Apply(ctx, tenantA.ID, userA.ID, "v2", map[string]bool{domain.PurposeProgressPhotos: true}); err != nil {
		t.Fatalf("conceder v2: %v", err)
	}
	if got, _ := consents.ActivePurposes(ctx, tenantA.ID, userA.ID, "v2"); len(got) != 1 || got[0] != domain.PurposeProgressPhotos {
		t.Fatalf("só progress_photos está vigente na v2, obtive %v", got)
	}
}
