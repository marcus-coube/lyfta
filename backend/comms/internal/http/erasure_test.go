package http_test

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"

	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/security"
)

const erasureTestToken = "token-m2m-de-teste"

func erasureRouter(t *testing.T) http.Handler {
	t.Helper()
	pool := testDevicesPool(t)
	verifier, err := security.NewJWTVerifier(newTestKeys(t))
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	logger := slog.New(slog.DiscardHandler)
	return chttp.NewRouter(logger, []string{"*"}, verifier, erasureTestToken,
		nil, nil, nil, nil, nil, chttp.NewErasureHandler(logger, repo.NewErasureRepo(pool)))
}

func doErase(router http.Handler, token, userID, tenantID string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, "/internal/v1/users/"+userID+"?tenant_id="+tenantID, nil)
	if token != "" {
		req.Header.Set("X-Internal-Token", token)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

// TestEraseUserEndpoint cobre o contrato M2M da exclusão de conta (P4.5): sem
// token 401, id inválido 400, caminho feliz 204 e repetível.
func TestEraseUserEndpoint(t *testing.T) {
	router := erasureRouter(t)
	tenantID, userID := uuid.NewString(), uuid.NewString()

	if rec := doErase(router, "", userID, tenantID); rec.Code != http.StatusUnauthorized {
		t.Fatalf("sem token: esperava 401, veio %d", rec.Code)
	}
	if rec := doErase(router, "errado", userID, tenantID); rec.Code != http.StatusUnauthorized {
		t.Fatalf("token errado: esperava 401, veio %d", rec.Code)
	}
	if rec := doErase(router, erasureTestToken, "nao-e-uuid", tenantID); rec.Code != http.StatusBadRequest {
		t.Fatalf("id inválido: esperava 400, veio %d", rec.Code)
	}
	for i := 0; i < 2; i++ {
		if rec := doErase(router, erasureTestToken, userID, tenantID); rec.Code != http.StatusNoContent {
			t.Fatalf("tentativa %d: esperava 204, veio %d: %s", i+1, rec.Code, rec.Body.String())
		}
	}
}
