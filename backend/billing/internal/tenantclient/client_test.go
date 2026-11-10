package tenantclient

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestListPaginatesAndCaches(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Header.Get("X-Internal-Token") != "tok" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		resp := map[string]any{}
		if r.URL.Query().Get("after") == "" {
			resp["items"] = []Tenant{{ID: "a", Timezone: "America/Sao_Paulo"}}
			resp["next_cursor"] = "a"
		} else {
			resp["items"] = []Tenant{{ID: "b", Timezone: "Europe/Lisbon"}}
		}
		_ = json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	now := time.Date(2030, 1, 1, 0, 0, 0, 0, time.UTC)
	c := NewClient(srv.URL, "tok", 10*time.Minute)
	c.now = func() time.Time { return now }

	got, err := c.List(context.Background())
	if err != nil || len(got) != 2 || got[1].Timezone != "Europe/Lisbon" {
		t.Fatalf("List = %+v, %v", got, err)
	}
	if calls != 2 {
		t.Fatalf("2 páginas = 2 chamadas, veio %d", calls)
	}
	if _, err := c.List(context.Background()); err != nil || calls != 2 {
		t.Fatalf("dentro do TTL deveria usar o cache (calls=%d, err=%v)", calls, err)
	}
	now = now.Add(11 * time.Minute)
	if _, err := c.List(context.Background()); err != nil || calls != 4 {
		t.Fatalf("após o TTL deveria consultar de novo (calls=%d, err=%v)", calls, err)
	}
}

func TestListIdentityError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()
	if _, err := NewClient(srv.URL, "tok", time.Minute).List(context.Background()); err == nil {
		t.Fatal("esperava erro quando o identity falha")
	}
}
