package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// internalCall chama as rotas M2M com o token interno (ou sem ele).
func (e *env) internalCall(t *testing.T, method, path, token, body string) resp {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("X-Internal-Token", token)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return resp{status: rec.Code, body: out}
}

// TestPendingAndEraseStudent: fatura em aberto bloqueia (pending), quitada
// libera; a exclusão cancela assinatura e fatura futura, retém o titular com
// "conta excluída", deixa a fatura paga intacta e é idempotente (Aceite P7.5).
func TestPendingAndEraseStudent(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	ana := e.addStudent("Ana")
	r := e.subscribe(t, owner, ana, plan, 15, "2026-11-10")
	r.wantStatus(t, http.StatusCreated, "")
	sub, inv := r.obj("subscription")["id"].(string), r.obj("invoice")["id"].(string)
	q := "?tenant_id=" + e.tenant
	pendingURL := "/internal/v1/users/" + ana + "/pending" + q
	deleteURL := "/internal/v1/users/" + ana + q

	// Token errado/ausente e ids inválidos.
	e.internalCall(t, http.MethodGet, pendingURL, "", "").wantStatus(t, http.StatusUnauthorized, "")
	e.internalCall(t, http.MethodDelete, deleteURL, "errado", "{}").wantStatus(t, http.StatusUnauthorized, "")
	e.internalCall(t, http.MethodGet, "/internal/v1/users/x/pending"+q, testInternalToken, "").wantStatus(t, http.StatusBadRequest, "validation_error")
	e.internalCall(t, http.MethodDelete, deleteURL, testInternalToken, `{"name":"","email":""}`).wantStatus(t, http.StatusBadRequest, "validation_error")

	// Fatura aberta: pendente. Vencida: também.
	p := e.internalCall(t, http.MethodGet, pendingURL, testInternalToken, "")
	p.wantStatus(t, http.StatusOK, "")
	if p.body["pending"] != true || p.body["open_invoices"] != float64(1) || p.body["overdue_invoices"] != float64(0) {
		t.Fatalf("pending com fatura aberta: %+v", p.body)
	}
	e.execSQL(t, `UPDATE invoices SET status = 'overdue' WHERE id = $1`, inv)
	p = e.internalCall(t, http.MethodGet, pendingURL, testInternalToken, "")
	if p.body["pending"] != true || p.body["overdue_invoices"] != float64(1) {
		t.Fatalf("pending com fatura vencida: %+v", p.body)
	}

	// Quitada (baixa manual) libera.
	e.execSQL(t, `UPDATE invoices SET status = 'open' WHERE id = $1`, inv)
	e.call(t, http.MethodPost, "/v1/billing/invoices/"+inv+"/payments", owner, map[string]any{}).wantStatus(t, http.StatusCreated, "")
	p = e.internalCall(t, http.MethodGet, pendingURL, testInternalToken, "")
	if p.body["pending"] != false {
		t.Fatalf("aluno quitado não deveria ter pendência: %+v", p.body)
	}

	// Fatura futura aberta (janeiro) que a exclusão deve cancelar.
	jan := uuid.NewString()
	e.execSQL(t, `INSERT INTO invoices (id, tenant_id, subscription_id, student_id, period, due_date, amount_cents)
		VALUES ($1, $2, $3, $4, '2027-01', '2027-01-15', 15000)`, jan, e.tenant, sub, ana)

	body := `{"name":"Ana Souza","email":"ana.souza@x.com"}`
	e.internalCall(t, http.MethodDelete, deleteURL, testInternalToken, body).wantStatus(t, http.StatusNoContent, "")
	// Repetir (com outro nome) é 204 e não sobrescreve o que foi retido.
	e.internalCall(t, http.MethodDelete, deleteURL, testInternalToken, `{"name":"deleted","email":"x@y.z"}`).wantStatus(t, http.StatusNoContent, "")

	s := e.call(t, http.MethodGet, "/v1/billing/subscriptions/"+sub, owner, nil)
	s.wantStatus(t, http.StatusOK, "")
	c := s.body["customer"].(map[string]any)
	if s.body["status"] != "canceled" || c["account_deleted"] != true || c["name"] != "Ana Souza" || c["email"] != "ana.souza@x.com" {
		t.Fatalf("assinatura/titular após exclusão: %+v", s.body)
	}
	paid := e.call(t, http.MethodGet, "/v1/billing/invoices/"+inv, owner, nil)
	pc := paid.body["customer"].(map[string]any)
	if paid.body["status"] != "paid" || pc["account_deleted"] != true || pc["name"] != "Ana Souza" {
		t.Fatalf("fatura paga deve seguir legível: %+v", paid.body)
	}
	if got := e.call(t, http.MethodGet, "/v1/billing/invoices/"+jan, owner, nil); got.body["status"] != "canceled" {
		t.Fatalf("fatura futura aberta deveria ser cancelada: %+v", got.body)
	}

	// Aluno sem registro financeiro: 204 e nada é criado.
	nobody := uuid.NewString()
	e.internalCall(t, http.MethodDelete, "/internal/v1/users/"+nobody+q, testInternalToken, body).wantStatus(t, http.StatusNoContent, "")
	e.internalCall(t, http.MethodGet, "/internal/v1/users/"+nobody+"/pending"+q, testInternalToken, "").wantStatus(t, http.StatusOK, "")
}

// TestEraseStudentIsTenantScoped: a exclusão em outro tenant não toca o aluno
// de A (RLS).
func TestEraseStudentIsTenantScoped(t *testing.T) {
	e := newEnv(t)
	owner := e.token(t, e.tenant, uuid.NewString(), "owner")
	plan := e.createPlan(t, owner)
	ana := e.addStudent("Ana")
	e.subscribe(t, owner, ana, plan, 15, "2026-11-10").wantStatus(t, http.StatusCreated, "")

	other := uuid.NewString()
	e.internalCall(t, http.MethodDelete, "/internal/v1/users/"+ana+"?tenant_id="+other, testInternalToken,
		`{"name":"X","email":"x@x.com"}`).wantStatus(t, http.StatusNoContent, "")
	p := e.internalCall(t, http.MethodGet, "/internal/v1/users/"+ana+"/pending?tenant_id="+other, testInternalToken, "")
	if p.body["pending"] != false {
		t.Fatalf("outro tenant não vê faturas de A: %+v", p.body)
	}
	list := e.call(t, http.MethodGet, "/v1/billing/subscriptions?student_id="+ana, owner, nil)
	if it := list.items(); len(it) != 1 || it[0].(map[string]any)["status"] != "active" {
		t.Fatalf("assinatura de A não pode mudar: %+v", list.body)
	}
}
