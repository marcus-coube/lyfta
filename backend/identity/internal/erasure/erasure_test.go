package erasure_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/marcus-coube/lyfta/identity/internal/erasure"
)

// TestEraseCallsEveryServiceAndReportsFailures: o cliente manda o token M2M e o
// tenant, não para no primeiro erro e nomeia quem falhou.
func TestEraseCallsEveryServiceAndReportsFailures(t *testing.T) {
	var gotPath, gotToken, gotTenant string
	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotToken, gotTenant = r.URL.Path, r.Header.Get("X-Internal-Token"), r.URL.Query().Get("tenant_id")
		w.WriteHeader(http.StatusNoContent)
	}))
	defer ok.Close()
	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer down.Close()

	c := erasure.New("segredo", []erasure.Target{
		{Name: "assessment", BaseURL: down.URL},
		{Name: "workout", BaseURL: ok.URL},
	})
	failed := c.Erase(context.Background(), "tenant-1", "user-1", erasure.Profile{})

	if len(failed) != 1 || failed[0] != "assessment" {
		t.Fatalf("esperava só assessment falhando, obtive %v", failed)
	}
	if gotPath != "/internal/v1/users/user-1" || gotToken != "segredo" || gotTenant != "tenant-1" {
		t.Fatalf("chamada ao workout errada: path=%q token=%q tenant=%q", gotPath, gotToken, gotTenant)
	}
}

// TestEraseSendsProfileOnlyToBilling: só o alvo com Profile recebe nome e
// e-mail no corpo; os outros serviços não recebem dado pessoal (ADR-017 §5).
func TestEraseSendsProfileOnlyToBilling(t *testing.T) {
	var billingBody, workoutBody string
	capture := func(dst *string) *httptest.Server {
		return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw, _ := io.ReadAll(r.Body)
			*dst = string(raw)
			w.WriteHeader(http.StatusNoContent)
		}))
	}
	billing, workout := capture(&billingBody), capture(&workoutBody)
	defer billing.Close()
	defer workout.Close()

	c := erasure.New("segredo", []erasure.Target{
		{Name: "workout", BaseURL: workout.URL},
		{Name: "billing", BaseURL: billing.URL, Profile: true},
	})
	if failed := c.Erase(context.Background(), "t", "u", erasure.Profile{Name: "Ana", Email: "ana@x.com"}); len(failed) != 0 {
		t.Fatalf("não deveria falhar: %v", failed)
	}
	var got erasure.Profile
	if err := json.Unmarshal([]byte(billingBody), &got); err != nil || got.Name != "Ana" || got.Email != "ana@x.com" {
		t.Fatalf("corpo do billing: %q (%v)", billingBody, err)
	}
	if workoutBody != "" {
		t.Fatalf("workout não deve receber dado pessoal: %q", workoutBody)
	}
}

// TestPending: consulta o billing com o token M2M; erro HTTP vira erro; sem
// billing configurado nunca há pendência.
func TestPending(t *testing.T) {
	var gotPath, gotToken, gotTenant string
	billing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotToken, gotTenant = r.URL.Path, r.Header.Get("X-Internal-Token"), r.URL.Query().Get("tenant_id")
		_, _ = w.Write([]byte(`{"pending":true,"open_invoices":1,"overdue_invoices":2}`))
	}))
	defer billing.Close()

	c := erasure.New("segredo", nil).WithBilling(billing.URL)
	p, err := c.Pending(context.Background(), "tenant-1", "user-1")
	if err != nil || !p.Pending || p.OpenInvoices != 1 || p.OverdueInvoices != 2 {
		t.Fatalf("pending: %+v %v", p, err)
	}
	if gotPath != "/internal/v1/users/user-1/pending" || gotToken != "segredo" || gotTenant != "tenant-1" {
		t.Fatalf("chamada errada: path=%q token=%q tenant=%q", gotPath, gotToken, gotTenant)
	}

	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer down.Close()
	if _, err := erasure.New("x", nil).WithBilling(down.URL).Pending(context.Background(), "t", "u"); err == nil {
		t.Fatal("billing com erro deveria virar erro")
	}
	if p, err := erasure.New("x", nil).Pending(context.Background(), "t", "u"); err != nil || p.Pending {
		t.Fatalf("sem billing configurado não há pendência: %+v %v", p, err)
	}
}
