package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// TestPendingStudentsRequiresInternalToken cobre a autenticação M2M (ADR-013
// §4): sem X-Internal-Token (ou com o valor errado), 401 — mesmo sem tocar o
// banco, então não precisa de pool real.
func TestPendingStudentsRequiresInternalToken(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	router := newTestRouterWithPool(t, publicPEM, nil)

	req := httptest.NewRequest(http.MethodGet, "/internal/v1/pending-students?since=2026-01-01T00:00:00Z&until=2026-01-02T00:00:00Z", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("esperava 401 sem X-Internal-Token, veio %d", rec.Code)
	}

	req2 := httptest.NewRequest(http.MethodGet, "/internal/v1/pending-students?since=2026-01-01T00:00:00Z&until=2026-01-02T00:00:00Z", nil)
	req2.Header.Set("X-Internal-Token", "token-errado")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusUnauthorized {
		t.Fatalf("esperava 401 com token errado, veio %d", rec2.Code)
	}
}

// TestPendingStudentsRejectsBadRange cobre a validação dos parâmetros
// obrigatórios (since/until) com o token certo.
func TestPendingStudentsRejectsBadRange(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	router := newTestRouterWithPool(t, publicPEM, nil)
	validTenant := uuid.NewString()

	cases := []struct {
		name  string
		query string
	}{
		{"since ausente", "?until=2026-01-02T00:00:00Z&tenant_id=" + validTenant},
		{"until ausente", "?since=2026-01-01T00:00:00Z&tenant_id=" + validTenant},
		{"until antes de since", "?since=2026-01-02T00:00:00Z&until=2026-01-01T00:00:00Z&tenant_id=" + validTenant},
		{"tenant_id ausente", "?since=2026-01-01T00:00:00Z&until=2026-01-02T00:00:00Z"},
		{"tenant_id inválido", "?since=2026-01-01T00:00:00Z&until=2026-01-02T00:00:00Z&tenant_id=nao-e-uuid"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/internal/v1/pending-students"+tc.query, nil)
			req.Header.Set("X-Internal-Token", testInternalToken)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("esperava 400, veio %d: %s", rec.Code, rec.Body.String())
			}
		})
	}
}

// TestPendingStudentsHappyPathOverHTTP cobre o Aceite do passo 3 da P3.4 pelo
// contrato HTTP: aluno com plano ativo e sem sessão no intervalo aparece,
// tenant_id/student_id vêm certos. Precisa de Postgres real (a consulta
// atravessa a função SQL SECURITY DEFINER da migration 0016).
func TestPendingStudentsHappyPathOverHTTP(t *testing.T) {
	pool := testPool(t)
	publicPEM, _ := newTestKeys(t)
	router := newTestRouterWithPool(t, publicPEM, pool)

	tenantID := uuid.NewString()
	studentID := uuid.NewString()
	plans := repo.NewPlanRepo(pool)

	plan, err := plans.CreatePlan(t.Context(), domain.Plan{
		TenantID: tenantID, StudentID: studentID, CoachID: uuid.NewString(), Title: "Plano ativo",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(t.Context(), tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	if _, err := plans.AddDay(t.Context(), domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0,
	}); err != nil {
		t.Fatalf("criar dia: %v", err)
	}
	if err := repo.WithTenant(t.Context(), pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(t.Context(), `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id)
			VALUES ($1, $2, $3, $4)`,
			tenantID, studentID, plan.ID, version.ID)
		return err
	}); err != nil {
		t.Fatalf("gravar student_plan_state: %v", err)
	}

	since := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	until := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)

	req := httptest.NewRequest(http.MethodGet, "/internal/v1/pending-students?since="+since+"&until="+until+"&tenant_id="+tenantID, nil)
	req.Header.Set("X-Internal-Token", testInternalToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d: %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Items []struct {
			TenantID  string `json:"tenant_id"`
			StudentID string `json:"student_id"`
		} `json:"items"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatalf("decodificar resposta: %v", err)
	}
	found := false
	for _, it := range payload.Items {
		if it.TenantID == tenantID && it.StudentID == studentID {
			found = true
		}
	}
	if !found {
		t.Fatalf("esperava encontrar tenant=%s student=%s na resposta, veio %+v", tenantID, studentID, payload.Items)
	}
}
