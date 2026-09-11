package http_test

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/security"
)

// signToken emite um access token com as mesmas claims do identity
// (ADR-002) — mesmo padrão do assessment (internal/http/router_test.go).
func signToken(t *testing.T, priv ed25519.PrivateKey, tenantID, subject string, roles []string) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute)),
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

// newTestKeys gera um par ed25519 efêmero e devolve o PEM da pública (o
// formato que chega por JWT_PUBLIC_KEY) — mesmo padrão do assessment.
func newTestKeys(t *testing.T) string {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	pubBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal chave pública: %v", err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes}))
}

// newTestRouter monta o roteador com os handlers de chat vazios (nil): os
// três testes deste arquivo só exercitam /healthz e /v1/whoami — a
// integração real do chat (REST+WS) mora em chat_integration_test.go, que
// precisa de Postgres/Redis de verdade e por isso constrói o roteador com
// handlers reais.
func newTestRouter(t *testing.T) http.Handler {
	t.Helper()
	verifier, err := security.NewJWTVerifier(newTestKeys(t))
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}
	logger := slog.New(slog.DiscardHandler)
	var conversationHandler *chttp.ConversationHandler
	var mediaHandler *chttp.MediaHandler
	var wsHandler *chttp.WSHandler
	var checkinHandler *chttp.CheckinHandler
	var deviceHandler *chttp.DeviceHandler
	return chttp.NewRouter(logger, []string{"*"}, verifier, conversationHandler, mediaHandler, wsHandler, checkinHandler, deviceHandler)
}

func TestHealthzIsPublic(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestRouter(t).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 em /healthz, veio %d", rec.Code)
	}
}

func TestWhoamiRejectsMissingToken(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestRouter(t).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/whoami", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("esperava 401, veio %d", rec.Code)
	}
}

func TestWhoamiAcceptsValidToken(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	pubBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal chave pública: %v", err)
	}
	pubPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes}))

	verifier, err := security.NewJWTVerifier(pubPEM)
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}
	logger := slog.New(slog.DiscardHandler)
	var conversationHandler *chttp.ConversationHandler
	var mediaHandler *chttp.MediaHandler
	var wsHandler *chttp.WSHandler
	var checkinHandler *chttp.CheckinHandler
	var deviceHandler *chttp.DeviceHandler
	handler := chttp.NewRouter(logger, []string{"*"}, verifier, conversationHandler, mediaHandler, wsHandler, checkinHandler, deviceHandler)

	token := signToken(t, priv, "tenant-a", "user-a", []string{"coach"})
	req := httptest.NewRequest(http.MethodGet, "/v1/whoami", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d — %s", rec.Code, rec.Body.String())
	}
}
