package http_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	ihttp "github.com/marcus-coube/lyfta/identity/internal/http"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// testPool abre um pool contra o Postgres de dev, igual ao usado em
// internal/repo/repo_test.go. Pula o teste se o banco não estiver acessível.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_identity?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		t.Skipf("banco indisponível para teste de integração: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// testSigner gera um par ed25519 efêmero, encoda em PEM e monta um
// security.JWTSigner por ele — exercita o mesmo parser de PEM usado em
// produção (backend/scripts/gen-keys.sh), sem depender de env/arquivo.
func testSigner(t *testing.T) *security.JWTSigner {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves de teste: %v", err)
	}

	privBytes, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		t.Fatalf("marshal chave privada: %v", err)
	}
	pubBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal chave pública: %v", err)
	}

	privPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privBytes}))
	pubPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes}))

	signer, err := security.NewJWTSigner(privPEM, pubPEM)
	if err != nil {
		t.Fatalf("criar signer de teste: %v", err)
	}
	return signer
}

func newTestServer(t *testing.T) (*httptest.Server, *security.JWTSigner) {
	t.Helper()
	pool := testPool(t)
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
	signer := testSigner(t)

	handler := ihttp.NewAuthHandler(
		logger,
		repo.NewTenantRepo(pool),
		repo.NewUserRepo(pool),
		repo.NewAuthRepo(pool),
		signer,
	)
	router := ihttp.NewRouter(logger, []string{"*"}, handler)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)
	return server, signer
}

func uniqueSlug(prefix string) string {
	return prefix + "-" + uuid.NewString()[:8]
}

func uniqueEmail(prefix string) string {
	return prefix + "+" + uuid.NewString()[:8] + "@example.com"
}

type jsonResponse struct {
	status int
	body   map[string]any
}

func doPost(t *testing.T, client *http.Client, url string, payload any) jsonResponse {
	t.Helper()
	b, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	resp, err := client.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	defer resp.Body.Close()

	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if body == nil {
		body = map[string]any{}
	}
	return jsonResponse{status: resp.StatusCode, body: body}
}

// --- Aceite: signup -> login -> refresh -> logout -------------------------

func TestSignupLoginRefreshLogout(t *testing.T) {
	server, _ := newTestServer(t)
	client := server.Client()

	email := uniqueEmail("owner")
	slug := uniqueSlug("academia")

	signupResp := doPost(t, client, server.URL+"/v1/tenants", map[string]any{
		"business_name": "Academia Teste",
		"slug":          slug,
		"name":          "Owner Teste",
		"email":         email,
		"password":      "senha12345",
	})
	if signupResp.status != http.StatusCreated {
		t.Fatalf("signup: esperava 201, obtive %d: %v", signupResp.status, signupResp.body)
	}
	tenantID, _ := signupResp.body["tenant_id"].(string)
	if tenantID == "" {
		t.Fatalf("signup: esperava tenant_id no corpo, obtive %v", signupResp.body)
	}
	if signupResp.body["access_token"] == "" || signupResp.body["refresh_token"] == "" {
		t.Fatalf("signup: esperava tokens no corpo, obtive %v", signupResp.body)
	}

	loginResp := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    email,
		"password": "senha12345",
	})
	if loginResp.status != http.StatusOK {
		t.Fatalf("login: esperava 200, obtive %d: %v", loginResp.status, loginResp.body)
	}
	refreshToken, _ := loginResp.body["refresh_token"].(string)
	if refreshToken == "" {
		t.Fatalf("login: esperava refresh_token, obtive %v", loginResp.body)
	}

	// Refresh deve rotacionar o token (novo refresh_token, diferente do usado).
	refreshResp := doPost(t, client, server.URL+"/v1/auth/refresh", map[string]any{
		"refresh_token": refreshToken,
		"tenant_id":     tenantID,
	})
	if refreshResp.status != http.StatusOK {
		t.Fatalf("refresh: esperava 200, obtive %d: %v", refreshResp.status, refreshResp.body)
	}
	newRefreshToken, _ := refreshResp.body["refresh_token"].(string)
	if newRefreshToken == "" || newRefreshToken == refreshToken {
		t.Fatalf("refresh: esperava novo refresh_token diferente do original")
	}

	// Reuso do refresh token antigo deve falhar (rotação revoga o usado).
	reuseResp := doPost(t, client, server.URL+"/v1/auth/refresh", map[string]any{
		"refresh_token": refreshToken,
		"tenant_id":     tenantID,
	})
	if reuseResp.status != http.StatusUnauthorized || reuseResp.body["code"] != "invalid_token" {
		t.Fatalf("reuso do refresh antigo: esperava 401 invalid_token, obtive %d %v", reuseResp.status, reuseResp.body)
	}

	// Logout com o refresh token vigente.
	logoutResp := doPost(t, client, server.URL+"/v1/auth/logout", map[string]any{
		"refresh_token": newRefreshToken,
		"tenant_id":     tenantID,
	})
	if logoutResp.status != http.StatusNoContent {
		t.Fatalf("logout: esperava 204, obtive %d: %v", logoutResp.status, logoutResp.body)
	}

	// Refresh após logout deve falhar.
	afterLogout := doPost(t, client, server.URL+"/v1/auth/refresh", map[string]any{
		"refresh_token": newRefreshToken,
		"tenant_id":     tenantID,
	})
	if afterLogout.status != http.StatusUnauthorized || afterLogout.body["code"] != "invalid_token" {
		t.Fatalf("refresh após logout: esperava 401 invalid_token, obtive %d %v", afterLogout.status, afterLogout.body)
	}
}

// --- Aceite: login com múltiplos tenants -----------------------------------

func TestLoginMultipleTenants(t *testing.T) {
	server, _ := newTestServer(t)
	client := server.Client()

	email := uniqueEmail("multi")
	password := "senha12345"

	var tenantIDs []string
	for i := 0; i < 2; i++ {
		resp := doPost(t, client, server.URL+"/v1/tenants", map[string]any{
			"business_name": fmt.Sprintf("Academia Multi %d", i),
			"slug":          uniqueSlug("academia-multi"),
			"name":          "Dono Multi",
			"email":         email,
			"password":      password,
		})
		if resp.status != http.StatusCreated {
			t.Fatalf("signup %d: esperava 201, obtive %d: %v", i, resp.status, resp.body)
		}
		tenantIDs = append(tenantIDs, resp.body["tenant_id"].(string))
	}

	// Login sem tenant_id: e-mail existe em 2 tenants -> 409 multiple_tenants.
	ambiguous := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    email,
		"password": password,
	})
	if ambiguous.status != http.StatusConflict || ambiguous.body["code"] != "multiple_tenants" {
		t.Fatalf("login ambíguo: esperava 409 multiple_tenants, obtive %d %v", ambiguous.status, ambiguous.body)
	}
	params, ok := ambiguous.body["params"].(map[string]any)
	if !ok {
		t.Fatalf("login ambíguo: esperava params no corpo, obtive %v", ambiguous.body)
	}
	tenants, ok := params["tenants"].([]any)
	if !ok || len(tenants) != 2 {
		t.Fatalf("login ambíguo: esperava lista de 2 tenants, obtive %v", params["tenants"])
	}

	// Login reenviando com tenant_id resolve.
	resolved := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":     email,
		"password":  password,
		"tenant_id": tenantIDs[0],
	})
	if resolved.status != http.StatusOK {
		t.Fatalf("login com tenant_id: esperava 200, obtive %d: %v", resolved.status, resolved.body)
	}
	if resolved.body["tenant_id"] != tenantIDs[0] {
		t.Fatalf("login com tenant_id: esperava tenant %s, obtive %v", tenantIDs[0], resolved.body["tenant_id"])
	}
}

// --- Aceite: senha errada ---------------------------------------------------

func TestLoginInvalidCredentials(t *testing.T) {
	server, _ := newTestServer(t)
	client := server.Client()

	email := uniqueEmail("wrongpass")
	signupResp := doPost(t, client, server.URL+"/v1/tenants", map[string]any{
		"business_name": "Academia Senha",
		"slug":          uniqueSlug("academia-senha"),
		"name":          "Dono Senha",
		"email":         email,
		"password":      "senhacorreta1",
	})
	if signupResp.status != http.StatusCreated {
		t.Fatalf("signup: esperava 201, obtive %d: %v", signupResp.status, signupResp.body)
	}

	resp := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    email,
		"password": "senhaerrada1",
	})
	if resp.status != http.StatusUnauthorized || resp.body["code"] != "invalid_credentials" {
		t.Fatalf("senha errada: esperava 401 invalid_credentials, obtive %d %v", resp.status, resp.body)
	}

	// E-mail inexistente também deve responder invalid_credentials (não vaza
	// se o e-mail existe ou não).
	respUnknown := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    uniqueEmail("nao-existe"),
		"password": "qualquercoisa1",
	})
	if respUnknown.status != http.StatusUnauthorized || respUnknown.body["code"] != "invalid_credentials" {
		t.Fatalf("e-mail inexistente: esperava 401 invalid_credentials, obtive %d %v", respUnknown.status, respUnknown.body)
	}
}

// --- Aceite: access token expirado é rejeitado ------------------------------

func TestExpiredAccessTokenRejected(t *testing.T) {
	_, signer := newTestServer(t)

	token, expiresAt, err := signer.SignWithExpiry("user-id", "tenant-id", []string{"owner"}, "pt-BR", time.Now().Add(-1*time.Minute))
	if err != nil {
		t.Fatalf("assinar token expirado: %v", err)
	}
	if !expiresAt.Before(time.Now()) {
		t.Fatalf("esperava expiresAt no passado, obtive %v", expiresAt)
	}

	if _, err := signer.Parse(token); err != security.ErrInvalidToken {
		t.Fatalf("esperava ErrInvalidToken ao validar token expirado, obtive %v", err)
	}
}
