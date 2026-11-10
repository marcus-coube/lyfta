package tenantsettings

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// A troca do modo de acesso vale em até o TTL (30 s, ADR-017 §3): dentro do
// prazo vem do cache, depois dele o identity é consultado de novo.
func TestCacheExpiraNoTTL(t *testing.T) {
	var calls atomic.Int32
	mode := AccessStatusOnly
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Header.Get("X-Internal-Token") != "tok" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if r.URL.Path == "/internal/v1/tenants/missing" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte(`{"id":"t1","timezone":"Europe/Lisbon","coach_billing_access":"` + mode + `"}`))
	}))
	defer srv.Close()

	now := time.Date(2026, 11, 10, 12, 0, 0, 0, time.UTC)
	c := NewClient(srv.URL, "tok", DefaultTTL)
	c.now = func() time.Time { return now }
	ctx := context.Background()

	s, err := c.Get(ctx, "t1")
	if err != nil || s.CoachBillingAccess != AccessStatusOnly || s.Location().String() != "Europe/Lisbon" {
		t.Fatalf("primeira leitura: %+v %v", s, err)
	}
	mode = AccessOwnStudents
	now = now.Add(29 * time.Second)
	if s, _ := c.Get(ctx, "t1"); s.CoachBillingAccess != AccessStatusOnly || calls.Load() != 1 {
		t.Fatalf("dentro do TTL deveria vir do cache: %+v (%d chamadas)", s, calls.Load())
	}
	now = now.Add(2 * time.Second)
	if s, _ := c.Get(ctx, "t1"); s.CoachBillingAccess != AccessOwnStudents || calls.Load() != 2 {
		t.Fatalf("passado o TTL deveria reler: %+v (%d chamadas)", s, calls.Load())
	}
	if _, err := c.Get(ctx, "missing"); !errors.Is(err, ErrTenantNotFound) {
		t.Fatalf("tenant desconhecido: %v", err)
	}
}

func TestFusoInvalidoCaiNoDefault(t *testing.T) {
	if got := (Settings{Timezone: "Marte/Olympus"}).Location().String(); got != "America/Sao_Paulo" {
		t.Fatalf("fuso inválido deveria cair em America/Sao_Paulo, veio %s", got)
	}
}
