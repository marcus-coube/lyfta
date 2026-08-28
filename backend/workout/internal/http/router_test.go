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
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	whttp "github.com/marcus-coube/lyfta/workout/internal/http"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
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
	return signTokenAs(t, priv, tenantID, "11111111-1111-1111-1111-111111111111", roles, expiresAt)
}

// signTokenAs é signToken com o `sub` escolhido: o builder (P1.4) distingue o
// coach dono do plano dos demais, e o aluno lê o plano pelo próprio subject.
func signTokenAs(t *testing.T, priv ed25519.PrivateKey, tenantID, subject string, roles []string, expiresAt time.Time) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
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
	// Sem pool: os testes deste arquivo não tocam o banco. Quem exercita a
	// biblioteca (exercises_test.go) passa um pool de verdade.
	return newTestRouterWithPool(t, publicPEM, nil)
}

func newTestRouterWithPool(t *testing.T, publicPEM string, pool *pgxpool.Pool) http.Handler {
	t.Helper()
	verifier, err := security.NewJWTVerifier(publicPEM)
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}
	// Assinar é operação offline: o presigner monta a URL sem falar com o
	// storage, então estes testes de handler não precisam de MinIO no ar.
	presigner, err := media.NewPresigner(media.Config{
		Endpoint: "http://localhost:9000", Region: "us-east-1", Bucket: "lyfta-media",
		AccessKey: "minioadmin", SecretKey: "minioadmin", UsePathStyle: true,
	})
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	logger := slog.New(slog.DiscardHandler)
	exercises := repo.NewExerciseRepo(pool)
	return whttp.NewRouter(logger, []string{"*"}, verifier,
		whttp.NewMediaHandler(logger, presigner),
		whttp.NewExerciseHandler(logger, exercises, presigner),
		whttp.NewPlanHandler(logger, repo.NewPlanRepo(pool), exercises, presigner),
	)
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

// presign chama POST /v1/media/presign com o token informado.
func presign(t *testing.T, router http.Handler, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/media/presign", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

// TestPresignHappyPath é o fluxo feliz do P1.2: o coach pede a URL de upload e
// recebe PUT assinado, headers obrigatórios e a URL de exibição. A chave fica
// sob a pasta do tenant da claim.
func TestPresignHappyPath(t *testing.T) {
	publicPEM, priv := newTestKeys(t)
	const tenantID = "22222222-2222-2222-2222-222222222222"
	token := signToken(t, priv, tenantID, []string{"coach"}, time.Now().Add(time.Minute))

	rec := presign(t, newTestRouter(t, publicPEM), token, `{"content_type":"image/gif","size_bytes":1024}`)
	if rec.Code != http.StatusOK {
		body, _ := io.ReadAll(rec.Body)
		t.Fatalf("esperava 200, veio %d: %s", rec.Code, body)
	}

	var payload struct {
		UploadURL string            `json:"upload_url"`
		Method    string            `json:"upload_method"`
		Headers   map[string]string `json:"required_headers"`
		Key       string            `json:"key"`
		MediaURL  string            `json:"media_url"`
		MediaType string            `json:"media_type"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatalf("decodificar resposta: %v", err)
	}
	if payload.Method != http.MethodPut {
		t.Fatalf("esperava upload por PUT, veio %q", payload.Method)
	}
	if !strings.HasPrefix(payload.Key, "tenants/"+tenantID+"/exercises/") || !strings.HasSuffix(payload.Key, ".gif") {
		t.Fatalf("chave fora do layout do P1.2: %q", payload.Key)
	}
	if payload.MediaType != "gif" {
		t.Fatalf("esperava media_type gif, veio %q", payload.MediaType)
	}
	if !strings.Contains(payload.UploadURL, "X-Amz-Signature") {
		t.Fatalf("upload_url não veio assinada: %q", payload.UploadURL)
	}
	if payload.Headers["Content-Type"] != "image/gif" || payload.Headers["Content-Length"] != "1024" {
		t.Fatalf("headers obrigatórios vieram errados: %+v", payload.Headers)
	}
	if payload.MediaURL == "" {
		t.Fatalf("media_url vazia")
	}
}

// TestPresignRejects cobre os casos de erro do endpoint: tipo fora da
// whitelist, arquivo acima de 50 MB, tamanho ausente e corpo inválido.
func TestPresignRejects(t *testing.T) {
	publicPEM, priv := newTestKeys(t)
	token := signToken(t, priv, "22222222-2222-2222-2222-222222222222", []string{"coach"}, time.Now().Add(time.Minute))
	router := newTestRouter(t, publicPEM)

	cases := []struct {
		name     string
		body     string
		status   int
		wantCode string
	}{
		{"tipo não permitido", `{"content_type":"application/pdf","size_bytes":1024}`, http.StatusUnsupportedMediaType, "unsupported_media_type"},
		{"acima do limite", `{"content_type":"video/mp4","size_bytes":` + strconv.FormatInt(media.MaxUploadBytes+1, 10) + `}`, http.StatusRequestEntityTooLarge, "file_too_large"},
		{"sem tamanho", `{"content_type":"video/mp4"}`, http.StatusBadRequest, "validation_error"},
		{"corpo inválido", `não é json`, http.StatusBadRequest, "invalid_body"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := presign(t, router, token, tc.body)
			if rec.Code != tc.status {
				t.Fatalf("esperava %d, veio %d", tc.status, rec.Code)
			}
			var payload struct {
				Code string `json:"code"`
			}
			if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
				t.Fatalf("decodificar erro: %v", err)
			}
			if payload.Code != tc.wantCode {
				t.Fatalf("esperava code %q, veio %q", tc.wantCode, payload.Code)
			}
		})
	}
}

// TestPresignIsCoachOnly: quem sobe mídia de exercício é o professor
// (ADR-010 §3) — o aluno recebe 403 mesmo com token válido.
func TestPresignIsCoachOnly(t *testing.T) {
	publicPEM, priv := newTestKeys(t)
	token := signToken(t, priv, "22222222-2222-2222-2222-222222222222", []string{"student"}, time.Now().Add(time.Minute))

	rec := presign(t, newTestRouter(t, publicPEM), token, `{"content_type":"image/gif","size_bytes":1024}`)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("esperava 403 para aluno, veio %d", rec.Code)
	}
}
