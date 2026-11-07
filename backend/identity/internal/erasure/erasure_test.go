package erasure_test

import (
	"context"
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
	failed := c.Erase(context.Background(), "tenant-1", "user-1")

	if len(failed) != 1 || failed[0] != "assessment" {
		t.Fatalf("esperava só assessment falhando, obtive %v", failed)
	}
	if gotPath != "/internal/v1/users/user-1" || gotToken != "segredo" || gotTenant != "tenant-1" {
		t.Fatalf("chamada ao workout errada: path=%q token=%q tenant=%q", gotPath, gotToken, gotTenant)
	}
}
