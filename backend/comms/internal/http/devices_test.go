package http_test

import (
	"context"
	"crypto/ed25519"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/security"
)

// Aceite do passo 1 da P3.4: POST /v1/devices registra (faz upsert) o token
// por tenant+user+platform. Mesmo padrão de infra dos demais testes de
// integração do serviço (Postgres real via httptest.NewServer).

func testDevicesPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_comms?sslmode=disable"
	}
	pool, err := repo.NewPool(context.Background(), dsn)
	if err != nil {
		chatSkipOrFail(t, "banco indisponível para teste de integração: "+err.Error())
		return nil
	}
	t.Cleanup(pool.Close)
	return pool
}

type deviceTokenEnvelope struct {
	ID       string `json:"id"`
	Platform string `json:"platform"`
	Locale   string `json:"locale"`
}

func newDeviceTestServer(t *testing.T) (*httptest.Server, ed25519.PrivateKey) {
	t.Helper()
	pool := testDevicesPool(t)
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	verifier, err := security.NewJWTVerifier(pemFromPublicKey(t, pub))
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}

	logger := slog.New(slog.DiscardHandler)
	deviceHandler := chttp.NewDeviceHandler(logger, repo.NewDeviceTokenRepo(pool))
	var conversationHandler *chttp.ConversationHandler
	var mediaHandler *chttp.MediaHandler
	var wsHandler *chttp.WSHandler
	var checkinHandler *chttp.CheckinHandler

	router := chttp.NewRouter(logger, []string{"*"}, verifier, "", conversationHandler, mediaHandler, wsHandler, checkinHandler, deviceHandler, nil)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)
	return server, priv
}

func TestDeviceRegisterUpsertsByPlatform(t *testing.T) {
	server, priv := newDeviceTestServer(t)
	tenantID, userID := uuid.NewString(), uuid.NewString()
	token := signToken(t, priv, tenantID, userID, []string{"student"})

	var first deviceTokenEnvelope
	doJSON(t, server, http.MethodPost, "/v1/devices", token, map[string]string{
		"platform": "android", "token": "fcm-token-1", "locale": "pt-BR",
	}, &first)
	if first.Platform != "android" || first.Locale != "pt-BR" {
		t.Fatalf("registro inicial veio errado: %+v", first)
	}

	// Reinstalar o app: mesmo user+platform, token novo — upsert, não um
	// segundo registro (unique da migration 0004).
	var second deviceTokenEnvelope
	doJSON(t, server, http.MethodPost, "/v1/devices", token, map[string]string{
		"platform": "android", "token": "fcm-token-2", "locale": "en",
	}, &second)
	if second.ID != first.ID {
		t.Fatalf("upsert deveria manter o mesmo id da linha (tenant+user+platform), veio %s != %s", second.ID, first.ID)
	}
	if second.Locale != "en" {
		t.Fatalf("upsert deveria atualizar o locale, veio %q", second.Locale)
	}
}

func TestDeviceRegisterValidation(t *testing.T) {
	server, priv := newDeviceTestServer(t)
	tenantID, userID := uuid.NewString(), uuid.NewString()
	token := signToken(t, priv, tenantID, userID, []string{"student"})

	if status := doJSONStatus(t, server, http.MethodPost, "/v1/devices", token, map[string]string{
		"platform": "windows", "token": "x", "locale": "pt-BR",
	}); status != http.StatusBadRequest {
		t.Fatalf("plataforma desconhecida deveria ser 400, veio %d", status)
	}
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/devices", token, map[string]string{
		"platform": "android", "token": "", "locale": "pt-BR",
	}); status != http.StatusBadRequest {
		t.Fatalf("token vazio deveria ser 400, veio %d", status)
	}
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/devices", token, map[string]string{
		"platform": "android", "token": "x", "locale": "fr",
	}); status != http.StatusBadRequest {
		t.Fatalf("locale fora dos 3 do lançamento deveria ser 400, veio %d", status)
	}
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/devices", "", map[string]string{
		"platform": "android", "token": "x", "locale": "pt-BR",
	}); status != http.StatusUnauthorized {
		t.Fatalf("sem token de auth deveria ser 401, veio %d", status)
	}
}
