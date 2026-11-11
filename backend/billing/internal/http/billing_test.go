package http_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/billing/internal/coachlink"
	bhttp "github.com/marcus-coube/lyfta/billing/internal/http"
	"github.com/marcus-coube/lyfta/billing/internal/repo"
	"github.com/marcus-coube/lyfta/billing/internal/security"
	"github.com/marcus-coube/lyfta/billing/internal/studentdir"
	"github.com/marcus-coube/lyfta/billing/internal/tenantsettings"
)

const testInternalToken = "test-internal-token"

// testPool abre o pool contra o Postgres de dev (lyfta_billing, migrations já
// aplicadas) como lyfta_app. Fora do CI pula se o banco não estiver
// acessível; no CI o ambiente é obrigatório.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_billing?sslmode=disable"
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

// fakeIdentity serve o M2M do identity que o billing consome: configuração
// do tenant, vínculo coach→alunos e ficha do aluno.
type fakeIdentity struct {
	mu       sync.Mutex
	access   string
	coach    map[string][]string
	students map[string][2]string // id → nome, e-mail
	down     bool
	server   *httptest.Server
}

func newFakeIdentity(t *testing.T) *fakeIdentity {
	t.Helper()
	f := &fakeIdentity{access: "status_only", coach: map[string][]string{}, students: map[string][2]string{}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.down {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if r.Header.Get("X-Internal-Token") != testInternalToken {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		p := r.URL.Path
		switch {
		case strings.HasPrefix(p, "/internal/v1/tenants/"):
			_ = json.NewEncoder(w).Encode(map[string]string{
				"id": strings.TrimPrefix(p, "/internal/v1/tenants/"), "timezone": "America/Sao_Paulo",
				"coach_billing_access": f.access})
		case strings.HasPrefix(p, "/internal/v1/coaches/"):
			coach := strings.TrimSuffix(strings.TrimPrefix(p, "/internal/v1/coaches/"), "/students")
			ids := f.coach[coach]
			if ids == nil {
				ids = []string{}
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"student_ids": ids})
		case strings.HasPrefix(p, "/internal/v1/students/"):
			id := strings.TrimPrefix(p, "/internal/v1/students/")
			s, ok := f.students[id]
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"id": id, "name": s[0], "email": s[1], "status": "active"})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeIdentity) set(fn func()) {
	f.mu.Lock()
	defer f.mu.Unlock()
	fn()
}

type env struct {
	h        http.Handler
	priv     ed25519.PrivateKey
	identity *fakeIdentity
	pool     *pgxpool.Pool
	tenant   string
	now      time.Time
}

// newEnv monta o router real com clientes HTTP apontando para o fakeIdentity
// (TTL 0: trocar o modo ou o vínculo vale na hora; o TTL tem teste próprio).
// O relógio fica em 2026-11-10 12:00 em São Paulo.
func newEnv(t *testing.T) *env {
	t.Helper()
	pool := testPool(t)
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKIXPublicKey(pub)
	verifier, err := security.NewJWTVerifier(string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})))
	if err != nil {
		t.Fatal(err)
	}
	identity := newFakeIdentity(t)
	sp, _ := time.LoadLocation("America/Sao_Paulo")
	e := &env{priv: priv, identity: identity, pool: pool, tenant: uuid.NewString(),
		now: time.Date(2026, 11, 10, 12, 0, 0, 0, sp)}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	billing := bhttp.NewBillingHandler(logger,
		repo.NewPlanRepo(pool), repo.NewSubscriptionRepo(pool), repo.NewInvoiceRepo(pool), repo.NewErasureRepo(pool),
		tenantsettings.NewClient(identity.server.URL, testInternalToken, 0),
		studentdir.NewClient(identity.server.URL, testInternalToken),
		coachlink.NewClient(identity.server.URL, testInternalToken, 0),
		func() time.Time { return e.now })
	e.h = bhttp.NewRouter(logger, []string{"*"}, verifier, testInternalToken, billing)
	return e
}

func (e *env) token(t *testing.T, tenant, subject string, roles ...string) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{Subject: subject, ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute))},
		TenantID:         tenant, Roles: roles,
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims).SignedString(e.priv)
	if err != nil {
		t.Fatal(err)
	}
	return signed
}

type resp struct {
	status int
	body   map[string]any
}

func (e *env) call(t *testing.T, method, path, token string, payload any, headers ...string) resp {
	t.Helper()
	var rd io.Reader
	if payload != nil {
		raw, _ := json.Marshal(payload)
		rd = bytes.NewReader(raw)
	}
	req := httptest.NewRequest(method, path, rd)
	req.Header.Set("Authorization", "Bearer "+token)
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	body := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	return resp{status: rec.Code, body: body}
}

func (r resp) obj(key string) map[string]any {
	m, _ := r.body[key].(map[string]any)
	return m
}

func (r resp) items() []any {
	l, _ := r.body["items"].([]any)
	return l
}

func (r resp) wantStatus(t *testing.T, status int, code string) {
	t.Helper()
	if r.status != status || (code != "" && r.body["code"] != code) {
		t.Fatalf("esperava %d %q, veio %d %+v", status, code, r.status, r.body)
	}
}

func (e *env) addStudent(name string) string {
	id := uuid.NewString()
	e.identity.set(func() { e.identity.students[id] = [2]string{name, strings.ToLower(name) + "@x.com"} })
	return id
}

func (e *env) execSQL(t *testing.T, sql string, args ...any) {
	t.Helper()
	err := repo.WithTenant(context.Background(), e.pool, e.tenant, func(tx pgx.Tx) error {
		_, err := tx.Exec(context.Background(), sql, args...)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
}

// createPlan cria um plano de R$ 150,00 como owner.
func (e *env) createPlan(t *testing.T, owner string) string {
	t.Helper()
	r := e.call(t, http.MethodPost, "/v1/billing/plans", owner, map[string]any{"name": "Mensal", "amount_cents": 15000})
	r.wantStatus(t, http.StatusCreated, "")
	return r.body["id"].(string)
}

func (e *env) subscribe(t *testing.T, token, student, plan string, dueDay int, startsOn string) resp {
	t.Helper()
	return e.call(t, http.MethodPost, "/v1/billing/subscriptions", token, map[string]any{
		"student_id": student, "billing_plan_id": plan, "due_day": dueDay, "starts_on": startsOn})
}

// TestOwnerFlow cobre o ciclo inteiro do owner: plano, assinatura com a
// fatura do mês, baixa idempotente, estorno, cancelamento e o status
// derivado — com cada transição auditável (nada é apagado).
func TestOwnerFlow(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	ana, bia := e.addStudent("Ana"), e.addStudent("Bia")

	// Ana: vence dia 15 (futuro) -> fatura aberta. Bia: vence dia 5, início
	// dia 1 -> a fatura nasce vencida.
	r := e.subscribe(t, owner, ana, plan, 15, "2026-11-10")
	r.wantStatus(t, http.StatusCreated, "")
	inv := r.obj("invoice")
	if inv["status"] != "open" || inv["due_date"] != "2026-11-15" || inv["period"] != "2026-11" || inv["amount_cents"] != float64(15000) {
		t.Fatalf("fatura do período corrente: %+v", inv)
	}
	if c := r.obj("subscription")["customer"].(map[string]any); c["name"] != "Ana" || c["email"] != "ana@x.com" || c["account_deleted"] != false {
		t.Fatalf("cópia do titular: %+v", c)
	}
	invAna := inv["id"].(string)
	r = e.subscribe(t, owner, bia, plan, 5, "2026-11-01")
	r.wantStatus(t, http.StatusCreated, "")
	invBia := r.obj("invoice")["id"].(string)
	if r.obj("invoice")["status"] != "overdue" {
		t.Fatalf("fatura de Bia deveria nascer vencida: %+v", r.obj("invoice"))
	}

	// Assinar de novo o mesmo aluno: 409; início em mês futuro: sem fatura.
	e.subscribe(t, owner, ana, plan, 15, "2026-11-10").wantStatus(t, http.StatusConflict, "subscription_exists")
	cris := e.addStudent("Cris")
	if r := e.subscribe(t, owner, cris, plan, 10, "2026-12-01"); r.status != http.StatusCreated || r.body["invoice"] != nil {
		t.Fatalf("início futuro não gera fatura: %d %+v", r.status, r.body)
	}

	// Status derivado, sem valores.
	st := e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+ana+","+bia+","+cris+","+uuid.NewString(), owner, nil)
	if st.status != http.StatusOK || st.body[ana] != "ok" || st.body[bia] != "delinquent" || st.body[cris] != "ok" {
		t.Fatalf("status: %d %+v", st.status, st.body)
	}

	// Baixa: Idempotency-Key repetido devolve o mesmo pagamento; fatura paga
	// sem chave (ou com outra) = 409.
	pay := func(key string) resp {
		h := []string{}
		if key != "" {
			h = []string{"Idempotency-Key", key}
		}
		return e.call(t, http.MethodPost, "/v1/billing/invoices/"+invAna+"/payments", owner,
			map[string]any{"paid_at": "2026-11-09", "note": "PIX no extrato"}, h...)
	}
	first := pay("key-1")
	first.wantStatus(t, http.StatusCreated, "")
	paymentID := first.obj("payment")["id"].(string)
	if first.obj("invoice")["status"] != "paid" || first.obj("payment")["amount_cents"] != float64(15000) || first.obj("payment")["method"] != "manual" {
		t.Fatalf("baixa: %+v", first.body)
	}
	replay := pay("key-1")
	if replay.status != http.StatusOK || replay.obj("payment")["id"] != paymentID {
		t.Fatalf("replay deveria devolver o mesmo pagamento: %d %+v", replay.status, replay.body)
	}
	pay("").wantStatus(t, http.StatusConflict, "invoice_already_paid")
	pay("key-2").wantStatus(t, http.StatusConflict, "invoice_already_paid")
	// A mesma chave em outra fatura é conflito, não replay.
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invBia+"/payments", owner, map[string]any{}, "Idempotency-Key", "key-1").
		wantStatus(t, http.StatusConflict, "idempotency_key_conflict")
	// Fatura paga não cancela.
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invAna+"/cancel", owner, nil).wantStatus(t, http.StatusConflict, "invoice_already_paid")
	// Data futura é inválida.
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invBia+"/payments", owner, map[string]any{"paid_at": "2026-12-01"}).
		wantStatus(t, http.StatusBadRequest, "validation_error")

	// Estorno: motivo obrigatório; volta a aberta (vence no futuro); duplo = 409.
	e.call(t, http.MethodPost, "/v1/billing/payments/"+paymentID+"/reverse", owner, map[string]any{}).wantStatus(t, http.StatusBadRequest, "validation_error")
	rev := e.call(t, http.MethodPost, "/v1/billing/payments/"+paymentID+"/reverse", owner, map[string]any{"note": "valor errado"})
	rev.wantStatus(t, http.StatusCreated, "")
	if rev.obj("invoice")["status"] != "open" || rev.obj("invoice")["paid_at"] != nil || rev.obj("payment")["reversal_of"] != paymentID {
		t.Fatalf("estorno: %+v", rev.body)
	}
	e.call(t, http.MethodPost, "/v1/billing/payments/"+paymentID+"/reverse", owner, map[string]any{"note": "de novo"}).
		wantStatus(t, http.StatusConflict, "payment_already_reversed")
	e.call(t, http.MethodPost, "/v1/billing/payments/"+rev.obj("payment")["id"].(string)+"/reverse", owner, map[string]any{"note": "x"}).
		wantStatus(t, http.StatusConflict, "payment_is_reversal")

	// Histórico auditável: pagamento original (com reversed_by) e estorno.
	detail := e.call(t, http.MethodGet, "/v1/billing/invoices/"+invAna, owner, nil)
	pays, _ := detail.body["payments"].([]any)
	if detail.status != http.StatusOK || len(pays) != 2 || pays[0].(map[string]any)["reversed_by"] != rev.obj("payment")["id"] {
		t.Fatalf("histórico de pagamentos: %+v", detail.body)
	}

	// Estorno de fatura vencida volta para vencida.
	bPay := e.call(t, http.MethodPost, "/v1/billing/invoices/"+invBia+"/payments", owner, map[string]any{})
	bPay.wantStatus(t, http.StatusCreated, "")
	if st := e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+bia, owner, nil); st.body[bia] != "ok" {
		t.Fatalf("Bia quitada deveria estar ok: %+v", st.body)
	}
	bRev := e.call(t, http.MethodPost, "/v1/billing/payments/"+bPay.obj("payment")["id"].(string)+"/reverse", owner, map[string]any{"note": "x"})
	if bRev.status != http.StatusCreated || bRev.obj("invoice")["status"] != "overdue" {
		t.Fatalf("estorno de vencida: %+v", bRev.body)
	}

	// Pausar/retomar; valor e vencimento novos não mexem na fatura existente.
	subAna := e.call(t, http.MethodGet, "/v1/billing/subscriptions?student_id="+ana, owner, nil).items()[0].(map[string]any)["id"].(string)
	e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subAna+"/resume", owner, nil).wantStatus(t, http.StatusConflict, "invalid_subscription_state")
	if r := e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subAna+"/pause", owner, nil); r.status != http.StatusOK || r.body["status"] != "paused" {
		t.Fatalf("pausar: %+v", r.body)
	}
	e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subAna+"/resume", owner, nil).wantStatus(t, http.StatusOK, "")
	pat := e.call(t, http.MethodPatch, "/v1/billing/subscriptions/"+subAna, owner, map[string]any{"amount_cents": 20000, "due_day": 20})
	if pat.status != http.StatusOK || pat.body["amount_cents"] != float64(20000) || pat.body["due_day"] != float64(20) {
		t.Fatalf("patch: %+v", pat.body)
	}
	if d := e.call(t, http.MethodGet, "/v1/billing/invoices/"+invAna, owner, nil); d.body["amount_cents"] != float64(15000) || d.body["due_date"] != "2026-11-15" {
		t.Fatalf("fatura existente não muda: %+v", d.body)
	}
	e.call(t, http.MethodPatch, "/v1/billing/subscriptions/"+subAna, owner, map[string]any{"due_day": 29}).wantStatus(t, http.StatusBadRequest, "validation_error")

	// Cancelar: cancela a aberta futura de Ana; a vencida de Bia fica.
	if r := e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subAna+"/cancel", owner, nil); r.status != http.StatusOK || r.body["status"] != "canceled" || r.body["canceled_at"] == nil {
		t.Fatalf("cancelar: %+v", r.body)
	}
	if d := e.call(t, http.MethodGet, "/v1/billing/invoices/"+invAna, owner, nil); d.body["status"] != "canceled" {
		t.Fatalf("fatura aberta futura deveria cancelar: %+v", d.body)
	}
	subBia := e.call(t, http.MethodGet, "/v1/billing/subscriptions?student_id="+bia, owner, nil).items()[0].(map[string]any)["id"].(string)
	e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subBia+"/cancel", owner, nil).wantStatus(t, http.StatusOK, "")
	if d := e.call(t, http.MethodGet, "/v1/billing/invoices/"+invBia, owner, nil); d.body["status"] != "overdue" {
		t.Fatalf("fatura vencida nunca é cancelada pela assinatura: %+v", d.body)
	}
	e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+subBia+"/cancel", owner, nil).wantStatus(t, http.StatusConflict, "invalid_subscription_state")
	// Cancelar a fatura vencida avulsa é com o owner.
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invBia+"/cancel", owner, nil).wantStatus(t, http.StatusOK, "")
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invBia+"/cancel", owner, nil).wantStatus(t, http.StatusConflict, "invoice_canceled")
	// Assinatura cancelada libera nova assinatura do mesmo aluno.
	e.subscribe(t, owner, ana, plan, 15, "2026-11-10").wantStatus(t, http.StatusCreated, "")
}

func TestPlansAndValidation(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	e.call(t, http.MethodPost, "/v1/billing/plans", owner, map[string]any{"name": " ", "amount_cents": 100}).wantStatus(t, http.StatusBadRequest, "validation_error")
	e.call(t, http.MethodPost, "/v1/billing/plans", owner, map[string]any{"name": "X", "amount_cents": 0}).wantStatus(t, http.StatusBadRequest, "validation_error")

	plan := e.createPlan(t, owner)
	up := e.call(t, http.MethodPut, "/v1/billing/plans/"+plan, owner, map[string]any{"name": "Trimestral", "amount_cents": 40000})
	if up.status != http.StatusOK || up.body["name"] != "Trimestral" || up.body["amount_cents"] != float64(40000) {
		t.Fatalf("PUT plano: %+v", up.body)
	}
	e.call(t, http.MethodPut, "/v1/billing/plans/"+uuid.NewString(), owner, map[string]any{"name": "X", "amount_cents": 1}).wantStatus(t, http.StatusNotFound, "not_found")

	st := e.addStudent("Duda")
	e.subscribe(t, owner, st, plan, 0, "2026-11-10").wantStatus(t, http.StatusBadRequest, "validation_error")
	e.subscribe(t, owner, st, plan, 10, "10/11/2026").wantStatus(t, http.StatusBadRequest, "validation_error")
	e.subscribe(t, owner, uuid.NewString(), plan, 10, "2026-11-10").wantStatus(t, http.StatusNotFound, "student_not_found")
	e.subscribe(t, owner, st, uuid.NewString(), 10, "2026-11-10").wantStatus(t, http.StatusNotFound, "not_found")

	// Plano arquivado some do filtro active e não aceita assinatura nova;
	// arquivar duas vezes é idempotente.
	e.call(t, http.MethodPost, "/v1/billing/plans/"+plan+"/archive", owner, nil).wantStatus(t, http.StatusOK, "")
	e.call(t, http.MethodPost, "/v1/billing/plans/"+plan+"/archive", owner, nil).wantStatus(t, http.StatusOK, "")
	if l := e.call(t, http.MethodGet, "/v1/billing/plans?active=true", owner, nil).items(); len(l) != 0 {
		t.Fatalf("plano arquivado na lista de ativos: %+v", l)
	}
	if l := e.call(t, http.MethodGet, "/v1/billing/plans", owner, nil).items(); len(l) != 1 {
		t.Fatalf("lista completa deveria manter o arquivado: %+v", l)
	}
	e.subscribe(t, owner, st, plan, 10, "2026-11-10").wantStatus(t, http.StatusConflict, "plan_archived")

	// Sem token: 401.
	e.call(t, http.MethodGet, "/v1/billing/plans", "lixo", nil).wantStatus(t, http.StatusUnauthorized, "unauthenticated")
}

// TestAccessMatrix cobre a matriz da P7.2 nos dois modos do coach e o aluno.
func TestAccessMatrix(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)

	coachID, otherCoach := uuid.NewString(), uuid.NewString()
	coach := e.token(t, e.tenant, coachID, "coach")
	mine, theirs := e.addStudent("Meu"), e.addStudent("Alheio")
	e.identity.set(func() { e.identity.coach[coachID] = []string{mine}; e.identity.coach[otherCoach] = []string{theirs} })

	// Faturas de dois alunos criadas pelo owner.
	invMine := e.subscribe(t, owner, mine, plan, 15, "2026-11-10").obj("invoice")["id"].(string)
	invTheirs := e.subscribe(t, owner, theirs, plan, 15, "2026-11-10").obj("invoice")["id"].(string)

	// status_only (padrão): só o selo, dos próprios alunos.
	for _, c := range []struct{ method, path string }{
		{http.MethodGet, "/v1/billing/plans"}, {http.MethodGet, "/v1/billing/invoices"},
		{http.MethodGet, "/v1/billing/invoices/" + invMine}, {http.MethodGet, "/v1/billing/subscriptions"},
		{http.MethodPost, "/v1/billing/invoices/" + invMine + "/payments"},
	} {
		e.call(t, c.method, c.path, coach, map[string]any{}).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	}
	st := e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+mine+","+theirs, coach, nil)
	if st.status != http.StatusOK || st.body[mine] != "ok" || len(st.body) != 1 {
		t.Fatalf("coach só vê status dos alunos dele: %d %+v", st.status, st.body)
	}

	// Trocar o modo vale na hora aqui (TTL 0; o TTL tem teste próprio).
	e.identity.set(func() { e.identity.access = "own_students" })
	if l := e.call(t, http.MethodGet, "/v1/billing/plans", coach, nil); l.status != http.StatusOK || len(l.items()) != 1 {
		t.Fatalf("coach lê planos: %d %+v", l.status, l.body)
	}
	list := e.call(t, http.MethodGet, "/v1/billing/invoices", coach, nil)
	if list.status != http.StatusOK || len(list.items()) != 1 || list.items()[0].(map[string]any)["id"] != invMine {
		t.Fatalf("coach só lista faturas dos alunos dele: %+v", list.body)
	}
	e.call(t, http.MethodGet, "/v1/billing/invoices?student_id="+theirs, coach, nil).wantStatus(t, http.StatusNotFound, "student_not_found")
	e.call(t, http.MethodGet, "/v1/billing/invoices/"+invTheirs, coach, nil).wantStatus(t, http.StatusNotFound, "student_not_found")
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invTheirs+"/payments", coach, map[string]any{}).wantStatus(t, http.StatusNotFound, "student_not_found")
	if subs := e.call(t, http.MethodGet, "/v1/billing/subscriptions", coach, nil).items(); len(subs) != 1 {
		t.Fatalf("coach só lista assinaturas dos alunos dele: %+v", subs)
	}

	// Coach com own_students dá baixa e assina aluno do vínculo...
	pay := e.call(t, http.MethodPost, "/v1/billing/invoices/"+invMine+"/payments", coach, map[string]any{"note": "dinheiro"})
	pay.wantStatus(t, http.StatusCreated, "")
	novo := e.addStudent("Novo")
	e.identity.set(func() { e.identity.coach[coachID] = []string{mine, novo} })
	e.subscribe(t, coach, novo, plan, 10, "2026-12-01").wantStatus(t, http.StatusCreated, "")
	// ...mas não o de outro coach, nem o que é só do owner.
	e.subscribe(t, coach, theirs, plan, 10, "2026-12-01").wantStatus(t, http.StatusNotFound, "student_not_found")
	paymentID := pay.obj("payment")["id"].(string)
	for _, c := range []struct{ method, path string }{
		{http.MethodPost, "/v1/billing/plans"}, {http.MethodPut, "/v1/billing/plans/" + plan},
		{http.MethodPost, "/v1/billing/plans/" + plan + "/archive"},
		{http.MethodPost, "/v1/billing/invoices/" + invMine + "/cancel"},
		{http.MethodPost, "/v1/billing/payments/" + paymentID + "/reverse"},
	} {
		e.call(t, c.method, c.path, coach, map[string]any{"name": "x", "amount_cents": 1, "note": "x"}).
			wantStatus(t, http.StatusForbidden, "billing_access_denied")
	}
	if st := e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+mine, coach, nil); st.body[mine] != "ok" {
		t.Fatalf("status em own_students: %+v", st.body)
	}

	// Voltar para status_only fecha de novo.
	e.identity.set(func() { e.identity.access = "status_only" })
	e.call(t, http.MethodGet, "/v1/billing/invoices", coach, nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")

	// Aluno: nada do financeiro da organização, só as próprias faturas
	// (sem `note` nem dados do titular).
	student := e.token(t, e.tenant, mine, "student")
	e.call(t, http.MethodGet, "/v1/billing/invoices", student, nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+mine, student, nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	me := e.call(t, http.MethodGet, "/v1/me/invoices", student, nil)
	if me.status != http.StatusOK || len(me.items()) != 1 {
		t.Fatalf("/me/invoices: %d %+v", me.status, me.body)
	}
	item := me.items()[0].(map[string]any)
	if item["id"] != invMine || item["status"] != "paid" || item["paid_at"] == nil {
		t.Fatalf("fatura do aluno: %+v", item)
	}
	for _, leaked := range []string{"note", "payments", "customer", "student_id"} {
		if _, has := item[leaked]; has {
			t.Fatalf("aluno não deveria ver %q: %+v", leaked, item)
		}
	}
	if other := e.call(t, http.MethodGet, "/v1/me/invoices", e.token(t, e.tenant, theirs, "student"), nil); len(other.items()) != 1 || other.items()[0].(map[string]any)["id"] != invTheirs {
		t.Fatalf("aluno só vê as próprias: %+v", other.body)
	}

	// identity fora do ar fecha o acesso (500), como no coachlink.
	e.identity.set(func() { e.identity.down = true })
	e.call(t, http.MethodGet, "/v1/billing/invoices", coach, nil).wantStatus(t, http.StatusInternalServerError, "internal_error")
	// O owner não depende do identity para listar.
	e.call(t, http.MethodGet, "/v1/billing/invoices", owner, nil).wantStatus(t, http.StatusOK, "")
}

func TestInvoicePaginationAndFilters(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	var students []string
	for _, n := range []string{"Um", "Dois", "Tres"} {
		id := e.addStudent(n)
		students = append(students, id)
		e.subscribe(t, owner, id, plan, 15, "2026-11-10").wantStatus(t, http.StatusCreated, "")
	}

	p1 := e.call(t, http.MethodGet, "/v1/billing/invoices?limit=2", owner, nil)
	cursor, _ := p1.body["next_cursor"].(string)
	if p1.status != http.StatusOK || len(p1.items()) != 2 || cursor == "" {
		t.Fatalf("página 1: %+v", p1.body)
	}
	p2 := e.call(t, http.MethodGet, "/v1/billing/invoices?limit=2&cursor="+cursor, owner, nil)
	if len(p2.items()) != 1 || p2.body["next_cursor"] != nil {
		t.Fatalf("página 2: %+v", p2.body)
	}
	seen := map[any]bool{}
	for _, it := range append(p1.items(), p2.items()...) {
		seen[it.(map[string]any)["id"]] = true
	}
	if len(seen) != 3 {
		t.Fatalf("paginação repetiu ou perdeu itens: %v", seen)
	}
	if l := e.call(t, http.MethodGet, "/v1/billing/invoices?status=paid", owner, nil).items(); len(l) != 0 {
		t.Fatalf("filtro status: %+v", l)
	}
	if l := e.call(t, http.MethodGet, "/v1/billing/invoices?period=2026-11&student_id="+students[0], owner, nil).items(); len(l) != 1 {
		t.Fatalf("filtro period+student: %+v", l)
	}
	e.call(t, http.MethodGet, "/v1/billing/invoices?status=bogus", owner, nil).wantStatus(t, http.StatusBadRequest, "validation_error")
	e.call(t, http.MethodGet, "/v1/billing/invoices?period=2026-13", owner, nil).wantStatus(t, http.StatusBadRequest, "validation_error")
	e.call(t, http.MethodGet, "/v1/billing/invoices?cursor=xx", owner, nil).wantStatus(t, http.StatusBadRequest, "invalid_cursor")
}

// TestCrossTenantIsolation: o owner de outro tenant não enxerga nem opera
// faturas e assinaturas de A (RLS + tenant só da claim).
func TestCrossTenantIsolation(t *testing.T) {
	e := newEnv(t)
	ownerA := e.token(t, e.tenant, uuid.NewString(), "owner")
	planA := e.createPlan(t, ownerA)
	st := e.addStudent("Ana")
	r := e.subscribe(t, ownerA, st, planA, 15, "2026-11-10")
	r.wantStatus(t, http.StatusCreated, "")
	inv, sub := r.obj("invoice")["id"].(string), r.obj("subscription")["id"].(string)

	ownerB := e.token(t, uuid.NewString(), uuid.NewString(), "owner")
	e.call(t, http.MethodGet, "/v1/billing/invoices/"+inv, ownerB, nil).wantStatus(t, http.StatusNotFound, "not_found")
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+inv+"/payments", ownerB, map[string]any{}).wantStatus(t, http.StatusNotFound, "not_found")
	e.call(t, http.MethodPost, "/v1/billing/subscriptions/"+sub+"/cancel", ownerB, nil).wantStatus(t, http.StatusNotFound, "not_found")
	if l := e.call(t, http.MethodGet, "/v1/billing/invoices", ownerB, nil).items(); len(l) != 0 {
		t.Fatalf("B vê faturas de A: %+v", l)
	}
	if l := e.call(t, http.MethodGet, "/v1/billing/plans", ownerB, nil).items(); len(l) != 0 {
		t.Fatalf("B vê planos de A: %+v", l)
	}
	if s := e.call(t, http.MethodGet, "/v1/billing/students/status?ids="+st, ownerB, nil); s.body[st] != "none" {
		t.Fatalf("B vê status de aluno de A: %+v", s.body)
	}
	// A mesma Idempotency-Key em tenants diferentes não colide.
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+inv+"/payments", ownerA, map[string]any{}, "Idempotency-Key", "k").wantStatus(t, http.StatusCreated, "")
}

// TestConcurrentPaymentsOnlyOneWins: duas baixas simultâneas da mesma
// fatura (sem chave) — a fatura é travada, então exatamente uma passa e a
// outra recebe 409; sobra um único pagamento.
func TestConcurrentPaymentsOnlyOneWins(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	r := e.subscribe(t, owner, e.addStudent("Ana"), plan, 15, "2026-11-10")
	inv := r.obj("invoice")["id"].(string)

	results := make(chan int, 2)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results <- e.call(t, http.MethodPost, "/v1/billing/invoices/"+inv+"/payments", owner, map[string]any{}).status
		}()
	}
	wg.Wait()
	close(results)
	created, conflict := 0, 0
	for s := range results {
		switch s {
		case http.StatusCreated:
			created++
		case http.StatusConflict:
			conflict++
		}
	}
	if created != 1 || conflict != 1 {
		t.Fatalf("esperava 1x201 e 1x409, veio %d e %d", created, conflict)
	}
	if d := e.call(t, http.MethodGet, "/v1/billing/invoices/"+inv, owner, nil); len(d.body["payments"].([]any)) != 1 {
		t.Fatalf("deveria haver um único pagamento: %+v", d.body)
	}
}

// TestBillingSummary cobre o Aceite da P8.1 no billing: números batem com um
// seed conhecido (recebido pelo `paid_at` no fuso do tenant, a receber por
// vencimento, vencido como estoque, série de 6 meses), coach recebe 403 mesmo
// com `own_students` e o tenant vizinho não aparece.
func TestBillingSummary(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	ana, bia, caio, dani := e.addStudent("Ana"), e.addStudent("Bia"), e.addStudent("Caio"), e.addStudent("Dani")

	// Novembro (mês corrente, relógio em 10/11): Ana e Dani abertas (vencem
	// 15/11), Bia vencida (venceu 5/11), Caio paga hoje.
	invOf := func(student string, day int) string {
		return e.subscribe(t, owner, student, plan, day, "2026-11-01").obj("invoice")["id"].(string)
	}
	invOf(ana, 15)
	invBia := invOf(bia, 5)
	invCaio := invOf(caio, 15)
	invOf(dani, 15)
	if st := e.call(t, http.MethodGet, "/v1/billing/invoices/"+invBia, owner, nil).body["status"]; st != "overdue" {
		t.Fatalf("seed: fatura de Bia deveria nascer vencida: %v", st)
	}
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+invCaio+"/payments", owner, map[string]any{}, "Idempotency-Key", uuid.NewString()).
		wantStatus(t, http.StatusCreated, "")

	// Meses anteriores, direto no banco: pagas na virada do mês em UTC que, em
	// São Paulo, ainda é o mês anterior; e uma vencida antiga de Bia.
	subOf := func(student string) string {
		var id string
		err := repo.WithTenant(context.Background(), e.pool, e.tenant, func(tx pgx.Tx) error {
			return tx.QueryRow(context.Background(), `SELECT id::text FROM subscriptions WHERE student_id = $1`, student).Scan(&id)
		})
		if err != nil {
			t.Fatal(err)
		}
		return id
	}
	old := func(student, period, due, status string, paidAt any) {
		e.execSQL(t, `INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents, status, paid_at)
			VALUES ($1, $2, $3, $4, $5, $6::date, 15000, $7, $8)`,
			uuid.NewString(), e.tenant, subOf(student), student, period, due, status, paidAt)
	}
	old(dani, "2026-10", "2026-10-15", "paid", "2026-11-01T01:00:00Z") // 31/10 22:00 em SP -> outubro
	old(caio, "2026-09", "2026-09-15", "paid", "2026-10-01T01:00:00Z") // 30/09 22:00 em SP -> setembro
	old(bia, "2026-08", "2026-08-05", "overdue", nil)

	sum := e.call(t, http.MethodGet, "/v1/billing/summary", owner, nil)
	if sum.status != http.StatusOK {
		t.Fatalf("summary: %d %+v", sum.status, sum.body)
	}
	for k, want := range map[string]float64{
		"received_cents": 15000, "to_receive_cents": 30000, "to_receive_count": 2,
		"overdue_cents": 30000, "overdue_count": 2, "delinquent_students": 1,
	} {
		if sum.body[k] != want {
			t.Errorf("%s = %v, esperava %v (%+v)", k, sum.body[k], want, sum.body)
		}
	}
	if sum.body["period"] != "2026-11" || sum.body["currency"] != "BRL" {
		t.Errorf("period/currency: %+v", sum.body)
	}
	series, _ := sum.body["received_series"].([]any)
	wantSeries := []float64{0, 0, 0, 15000, 15000, 15000}
	if len(series) != 6 {
		t.Fatalf("série: %+v", series)
	}
	for i, raw := range series {
		p := raw.(map[string]any)
		if p["received_cents"] != wantSeries[i] {
			t.Errorf("série[%d] = %+v, esperava %v", i, p, wantSeries[i])
		}
	}
	if first := series[0].(map[string]any)["period"]; first != "2026-06" {
		t.Errorf("a série começa em 2026-06, veio %v", first)
	}

	// Outro mês: a série termina nele; a receber é daquele mês.
	oct := e.call(t, http.MethodGet, "/v1/billing/summary?period=2026-10", owner, nil)
	if oct.status != http.StatusOK || oct.body["received_cents"] != float64(15000) || oct.body["to_receive_cents"] != float64(0) {
		t.Errorf("período 2026-10: %d %+v", oct.status, oct.body)
	}
	if s, _ := oct.body["received_series"].([]any); len(s) != 6 || s[5].(map[string]any)["period"] != "2026-10" {
		t.Errorf("série de 2026-10: %+v", oct.body["received_series"])
	}
	e.call(t, http.MethodGet, "/v1/billing/summary?period=2026-13", owner, nil).wantStatus(t, http.StatusBadRequest, "validation_error")

	// Coach: 403 em qualquer modo; aluno também; outro tenant não vê nada.
	coach := e.token(t, e.tenant, uuid.NewString(), "coach")
	e.call(t, http.MethodGet, "/v1/billing/summary", coach, nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	e.identity.set(func() { e.identity.access = "own_students" })
	e.call(t, http.MethodGet, "/v1/billing/summary", coach, nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	e.call(t, http.MethodGet, "/v1/billing/summary", e.token(t, e.tenant, ana, "student"), nil).wantStatus(t, http.StatusForbidden, "billing_access_denied")
	other := e.call(t, http.MethodGet, "/v1/billing/summary", e.token(t, uuid.NewString(), uuid.NewString(), "owner"), nil)
	if other.status != http.StatusOK || other.body["received_cents"] != float64(0) || other.body["overdue_count"] != float64(0) {
		t.Errorf("tenant vizinho: %d %+v", other.status, other.body)
	}
}
