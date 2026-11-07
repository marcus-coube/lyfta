package consent_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/marcus-coube/lyfta/assessment/internal/consent"
)

func TestHasPurpose(t *testing.T) {
	var gotPath, gotToken, gotTenant string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotToken, gotTenant = r.URL.Path, r.Header.Get("X-Internal-Token"), r.URL.Query().Get("tenant_id")
		_, _ = w.Write([]byte(`{"purposes":["terms","progress_photos"]}`))
	}))
	defer srv.Close()

	c := consent.NewClient(srv.URL, "segredo")
	ok, err := c.HasPurpose(context.Background(), "tenant-1", "user-1", "progress_photos")
	if err != nil || !ok {
		t.Fatalf("esperava consentimento vigente: ok=%v err=%v", ok, err)
	}
	if gotPath != "/internal/v1/users/user-1/consents" || gotToken != "segredo" || gotTenant != "tenant-1" {
		t.Fatalf("chamada errada: path=%q token=%q tenant=%q", gotPath, gotToken, gotTenant)
	}
	if ok, _ := c.HasPurpose(context.Background(), "tenant-1", "user-1", "health_data"); ok {
		t.Fatal("health_data não está na lista")
	}
}

func TestHasPurposeIdentityDown(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()
	if _, err := consent.NewClient(srv.URL, "x").HasPurpose(context.Background(), "t", "u", "progress_photos"); err == nil {
		t.Fatal("identity fora do ar deveria virar erro, não 'sem consentimento'")
	}
}
