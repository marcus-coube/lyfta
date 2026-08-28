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
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	whttp "github.com/marcus-coube/lyfta/workout/internal/http"
	"github.com/marcus-coube/lyfta/workout/internal/security"
)

// newTestKeys gera um par ed25519 efêmero e devolve o PEM da pública (o
// formato que chega por JWT_PUBLIC_KEY) junto da privada, que aqui faz o papel
// do identity assinando o token. Exercita o mesmo parser de PEM usado em
// produção, sem depender de env/arquivo.
func newTestKeys(t *testing.T) (publicPEM string, private ed25519.PrivateKey) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	pubBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal chave pública: %v", err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes})), priv
}

// signToken emite um access token com as mesmas claims do identity (ADR-002).
func signToken(t *testing.T, priv ed25519.PrivateKey, tenantID string, roles []string, expiresAt time.Time) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "11111111-1111-1111-1111-111111111111",
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
		TenantID: tenantID,
		Roles:    roles,
		Locale:   "pt-BR",
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims).SignedString(priv)
	if err != nil {
		t.Fatalf("assinar token: %v", err)
	}
	return signed
}

func newTestRouter(t *testing.T, publicPEM string) http.Handler {
	t.Helper()
	verifier, err := security.NewJWTVerifier(publicPEM)
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}
	return whttp.NewRouter(slog.New(slog.DiscardHandler), []string{"*"}, verifier)
}

func TestHealthzIsPublic(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	rec := httptest.NewRecorder()
	newTestRouter(t, publicPEM).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 em /healthz, veio %d", rec.Code)
	}
}

// TestWhoamiAcceptsIdentityToken é o fluxo feliz do esqueleto: um token
// assinado pelo identity é aceito aqui só com a chave pública (ADR-013 §4) e o
// tenant que o RLS vai usar vem da claim.
func TestWhoamiAcceptsIdentityToken(t *testing.T) {
	publicPEM, priv := newTestKeys(t)
	const tenantID = "22222222-2222-2222-2222-222222222222"
	token := signToken(t, priv, tenantID, []string{"coach"}, time.Now().Add(time.Minute))

	req := httptest.NewRequest(http.MethodGet, "/v1/whoami", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	newTestRouter(t, publicPEM).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		body, _ := io.ReadAll(rec.Body)
		t.Fatalf("esperava 200, veio %d: %s", rec.Code, body)
	}
	var payload struct {
		TenantID string   `json:"tenant_id"`
		Roles    []string `json:"roles"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatalf("decodificar resposta: %v", err)
	}
	if payload.TenantID != tenantID {
		t.Fatalf("tenant_id da claim deveria voltar %q, veio %q", tenantID, payload.TenantID)
	}
}

// TestWhoamiRejectsBadTokens cobre os casos de erro do middleware: sem header,
// assinado por outra chave e expirado — todos 401, sem detalhar o motivo.
func TestWhoamiRejectsBadTokens(t *testing.T) {
	publicPEM, priv := newTestKeys(t)
	_, otherPriv := newTestKeys(t)
	const tenantID = "22222222-2222-2222-2222-222222222222"

	cases := []struct {
		name   string
		header string
	}{
		{"sem header", ""},
		{"token de outra chave", "Bearer " + signToken(t, otherPriv, tenantID, []string{"coach"}, time.Now().Add(time.Minute))},
		{"token expirado", "Bearer " + signToken(t, priv, tenantID, []string{"coach"}, time.Now().Add(-time.Minute))},
		{"token sem tenant", "Bearer " + signToken(t, priv, "", []string{"coach"}, time.Now().Add(time.Minute))},
		{"lixo no header", "Bearer não-é-jwt"},
	}

	router := newTestRouter(t, publicPEM)
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/v1/whoami", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("esperava 401, veio %d", rec.Code)
			}
			var payload struct {
				Code string `json:"code"`
			}
			if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
				t.Fatalf("decodificar erro: %v", err)
			}
			if payload.Code != "unauthenticated" {
				t.Fatalf("esperava code unauthenticated, veio %q", payload.Code)
			}
		})
	}
}
