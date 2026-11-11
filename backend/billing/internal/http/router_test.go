package http_test

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	bhttp "github.com/marcus-coube/lyfta/billing/internal/http"
	"github.com/marcus-coube/lyfta/billing/internal/security"
)

func newTestRouter(t *testing.T) (http.Handler, ed25519.PrivateKey) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	verifier, err := security.NewJWTVerifier(string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})))
	if err != nil {
		t.Fatal(err)
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return bhttp.NewRouter(logger, []string{"http://localhost:*"}, verifier, nil), priv
}

func get(h http.Handler, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func sign(t *testing.T, priv ed25519.PrivateKey, tenantID string) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "user-1",
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute)),
		},
		TenantID: tenantID,
		Roles:    []string{"owner"},
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims).SignedString(priv)
	if err != nil {
		t.Fatal(err)
	}
	return signed
}

// O app web manda Idempotency-Key na baixa manual; o preflight tem de liberá-lo.
func TestCORSPreflightLiberaIdempotencyKey(t *testing.T) {
	h, _ := newTestRouter(t)
	req := httptest.NewRequest(http.MethodOptions, "/v1/billing/invoices/x/payments", nil)
	req.Header.Set("Origin", "http://localhost:5678")
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	req.Header.Set("Access-Control-Request-Headers", "authorization,content-type,idempotency-key")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:5678" {
		t.Fatalf("preflight recusado: Allow-Origin=%q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(strings.ToLower(got), "idempotency-key") {
		t.Fatalf("Idempotency-Key fora do Allow-Headers: %q", got)
	}
}

func TestHealthz(t *testing.T) {
	h, _ := newTestRouter(t)
	if rec := get(h, "/healthz", ""); rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d", rec.Code)
	}
}

func TestWhoamiDevolveTenantDoToken(t *testing.T) {
	h, priv := newTestRouter(t)
	rec := get(h, "/v1/whoami", sign(t, priv, "tenant-1"))
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d", rec.Code)
	}
	var body struct {
		UserID   string `json:"user_id"`
		TenantID string `json:"tenant_id"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.UserID != "user-1" || body.TenantID != "tenant-1" {
		t.Fatalf("claims inesperadas: %+v", body)
	}
}

func TestWhoamiRejeitaSemToken(t *testing.T) {
	h, _ := newTestRouter(t)
	if rec := get(h, "/v1/whoami", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("esperava 401, veio %d", rec.Code)
	}
}
