package http_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

func erase(router http.Handler, token, userID, tenantID string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, "/internal/v1/users/"+userID+"?tenant_id="+tenantID, nil)
	if token != "" {
		req.Header.Set("X-Internal-Token", token)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

// TestEraseUserRequiresInternalTokenAndValidIDs: sem token 401, id inválido
// 400 — nada disso toca o banco.
func TestEraseUserRequiresInternalTokenAndValidIDs(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	router := newTestRouterWithPool(t, publicPEM, nil)

	if rec := erase(router, "", uuid.NewString(), uuid.NewString()); rec.Code != http.StatusUnauthorized {
		t.Fatalf("sem token: esperava 401, veio %d", rec.Code)
	}
	if rec := erase(router, "errado", uuid.NewString(), uuid.NewString()); rec.Code != http.StatusUnauthorized {
		t.Fatalf("token errado: esperava 401, veio %d", rec.Code)
	}
	if rec := erase(router, testInternalToken, "nao-e-uuid", uuid.NewString()); rec.Code != http.StatusBadRequest {
		t.Fatalf("id inválido: esperava 400, veio %d", rec.Code)
	}
	if rec := erase(router, testInternalToken, uuid.NewString(), ""); rec.Code != http.StatusBadRequest {
		t.Fatalf("tenant ausente: esperava 400, veio %d", rec.Code)
	}
}

// TestEraseUserHappyPath: 204 e o plano do aluno fica desatribuído; repetir
// continua 204.
func TestEraseUserHappyPath(t *testing.T) {
	pool := testPool(t)
	publicPEM, _ := newTestKeys(t)
	router := newTestRouterWithPool(t, publicPEM, pool)

	tenantID, studentID := uuid.NewString(), uuid.NewString()
	plan, err := repo.NewPlanRepo(pool).CreatePlan(t.Context(), domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: uuid.NewString(), Title: "Plano da Maria",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}

	for i := 0; i < 2; i++ {
		if rec := erase(router, testInternalToken, studentID, tenantID); rec.Code != http.StatusNoContent {
			t.Fatalf("tentativa %d: esperava 204, veio %d: %s", i+1, rec.Code, rec.Body.String())
		}
	}

	var gotStudent, gotTitle string
	err = repo.WithTenant(t.Context(), pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(t.Context(), `SELECT student_id::text, title FROM workout_plans WHERE id = $1`, plan.ID).Scan(&gotStudent, &gotTitle)
	})
	if err != nil {
		t.Fatalf("ler plano: %v", err)
	}
	if gotStudent != repo.AnonymousUserID || gotTitle != "" {
		t.Fatalf("plano deveria estar desatribuído: student=%s title=%q", gotStudent, gotTitle)
	}
}
