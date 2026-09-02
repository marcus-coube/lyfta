package http_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	ahttp "github.com/marcus-coube/lyfta/assessment/internal/http"
	"github.com/marcus-coube/lyfta/assessment/internal/media"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
	"github.com/marcus-coube/lyfta/assessment/internal/security"
)

// testPool abre o pool contra o Postgres de dev, mesma regra do
// internal/repo: pula fora do CI, falha dentro dele (P0.7).
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_assessment?sslmode=disable"
	}
	pool, err := repo.NewPool(context.Background(), dsn)
	if err != nil {
		if os.Getenv("CI") != "" {
			t.Fatalf("banco indisponível no CI: %v", err)
		}
		t.Skipf("banco indisponível para teste de integração: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// newTestKeys gera um par ed25519 efêmero e devolve o PEM da pública (o
// formato que chega por JWT_PUBLIC_KEY) junto da privada, que aqui faz o papel
// do identity assinando o token.
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

// signTokenAs emite um access token com as mesmas claims do identity
// (ADR-002), com o `sub` escolhido — é o que distingue o aluno dono do
// registro dos demais.
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

func newTestRouterWithPool(t *testing.T, publicPEM string, pool *pgxpool.Pool) http.Handler {
	t.Helper()
	verifier, err := security.NewJWTVerifier(publicPEM)
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}
	// Assinar é operação offline: o presigner monta a URL sem falar com o
	// storage, então estes testes de handler não precisam de MinIO no ar
	// (mesmo critério do workout, P1.2).
	presigner, err := media.NewPresigner(media.Config{
		Endpoint: "http://localhost:9000", Region: "us-east-1", Bucket: "lyfta-media",
		AccessKey: "minioadmin", SecretKey: "minioadmin", UsePathStyle: true,
	})
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	logger := slog.New(slog.DiscardHandler)
	measurements := repo.NewMeasurementRepo(pool)
	bioimpedance := repo.NewBioimpedanceRepo(pool)
	photos := repo.NewPhotoRepo(pool)
	return ahttp.NewRouter(logger, []string{"*"}, verifier,
		ahttp.NewMeasurementHandler(logger, measurements),
		ahttp.NewBioimpedanceHandler(logger, bioimpedance),
		ahttp.NewPhotoHandler(logger, photos, presigner),
		ahttp.NewMediaHandler(logger, presigner),
		ahttp.NewSummaryHandler(logger, measurements, bioimpedance, photos),
	)
}

// assessmentActors monta o router com banco real e devolve os atores comuns
// às três suítes de recurso: o aluno dono, outro aluno do mesmo tenant, o
// coach do tenant e um coach de outro tenant.
type assessmentActors struct {
	handler   http.Handler
	tenantID  string
	student   string // token do aluno dono (sub = studentID)
	studentID string
	otherID   string // outro aluno do mesmo tenant, sem token (isolamento entre alunos)
	coach     string // token do coach do tenant
	foreign   string // token de coach de outro tenant
}

func newAssessmentActors(t *testing.T) assessmentActors {
	t.Helper()
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	handler := newTestRouterWithPool(t, publicPEM, pool)

	tenantID, tenantB := uuid.NewString(), uuid.NewString()
	studentID, otherID := uuid.NewString(), uuid.NewString()
	expires := time.Now().Add(time.Minute)

	return assessmentActors{
		handler:   handler,
		tenantID:  tenantID,
		student:   signTokenAs(t, priv, tenantID, studentID, []string{"student"}, expires),
		studentID: studentID,
		otherID:   otherID,
		coach:     signTokenAs(t, priv, tenantID, uuid.NewString(), []string{"coach"}, expires),
		foreign:   signTokenAs(t, priv, tenantB, uuid.NewString(), []string{"coach"}, expires),
	}
}

type apiError struct {
	Code   string         `json:"code"`
	Params map[string]any `json:"params"`
}

func do(t *testing.T, handler http.Handler, method, target, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("serializar corpo: %v", err)
		}
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, target, reader)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func decodeError(t *testing.T, rec *httptest.ResponseRecorder) apiError {
	t.Helper()
	var out apiError
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("decodificar erro: %v — %s", err, rec.Body.String())
	}
	return out
}

func TestHealthzIsPublic(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	rec := httptest.NewRecorder()
	newTestRouterWithPool(t, publicPEM, nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 em /healthz, veio %d", rec.Code)
	}
}

func TestWhoamiRejectsMissingToken(t *testing.T) {
	publicPEM, _ := newTestKeys(t)
	rec := do(t, newTestRouterWithPool(t, publicPEM, nil), http.MethodGet, "/v1/whoami", "", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("esperava 401, veio %d", rec.Code)
	}
}
