package repo_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// TestListAfterAllowsOneExtraRow protege a varredura M2M de tenants: o handler
// pede limit+1 (500+1) para saber se há próxima página, e o repositório não pode
// cortar essa linha extra — senão a página cheia nunca devolve cursor e os jobs
// do billing e do comms perdem todo tenant além dos primeiros 500.
func TestListAfterAllowsOneExtraRow(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenants := repo.NewTenantRepo(pool)

	// Garante mais de MaxTenantPageSize tenants (banco de dev costuma ter).
	var have int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM tenants`).Scan(&have); err != nil {
		t.Fatalf("contar tenants: %v", err)
	}
	for i := have; i <= repo.MaxTenantPageSize+1; i++ {
		label := fmt.Sprintf("paginacao-%d", i)
		if _, err := tenants.Create(ctx, domain.Tenant{Name: label, Slug: uniqueSlug(label), Locale: "pt-BR"}); err != nil {
			t.Fatalf("criar tenant: %v", err)
		}
	}

	rows, err := tenants.ListAfter(ctx, "", repo.MaxTenantPageSize+1)
	if err != nil {
		t.Fatalf("ListAfter: %v", err)
	}
	if len(rows) != repo.MaxTenantPageSize+1 {
		t.Fatalf("pediu %d linhas e veio %d: a linha extra do cursor foi cortada", repo.MaxTenantPageSize+1, len(rows))
	}
}
