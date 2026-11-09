package workoutclient_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/workoutclient"
)

func TestPendingStudentsHappyPath(t *testing.T) {
	var gotToken, gotSince, gotUntil string
	var gotTenants []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotToken = r.Header.Get("X-Internal-Token")
		gotSince = r.URL.Query().Get("since")
		gotUntil = r.URL.Query().Get("until")
		gotTenants = r.URL.Query()["tenant_id"]
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"items":[{"tenant_id":"t1","student_id":"s1"},{"tenant_id":"t1","student_id":"s2"}]}`))
	}))
	defer server.Close()

	client := workoutclient.NewClient(server.URL, "dev-internal-token")
	since := time.Date(2026, 9, 11, 0, 0, 0, 0, time.UTC)
	until := since.AddDate(0, 0, 1)

	items, err := client.PendingStudents(context.Background(), since, until, []string{"t1", "t2"})
	if err != nil {
		t.Fatalf("PendingStudents: %v", err)
	}
	if len(items) != 2 || items[0].StudentID != "s1" || items[1].StudentID != "s2" {
		t.Fatalf("itens inesperados: %+v", items)
	}
	if gotToken != "dev-internal-token" {
		t.Fatalf("esperava X-Internal-Token, veio %q", gotToken)
	}
	if gotSince == "" || gotUntil == "" {
		t.Fatalf("esperava since/until na query, veio since=%q until=%q", gotSince, gotUntil)
	}
	if len(gotTenants) != 2 || gotTenants[0] != "t1" || gotTenants[1] != "t2" {
		t.Fatalf("esperava tenant_id=t1&tenant_id=t2, veio %v", gotTenants)
	}
}

// TestPendingStudentsBatchesTenants: mais de 100 tenants viram várias chamadas
// (teto do workout) e os itens são concatenados; lista vazia não chama nada.
func TestPendingStudentsBatchesTenants(t *testing.T) {
	var calls, totalTenants int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		ids := r.URL.Query()["tenant_id"]
		if len(ids) > 100 {
			t.Errorf("lote com %d tenants, teto é 100", len(ids))
		}
		totalTenants += len(ids)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"items":[{"tenant_id":"` + ids[0] + `","student_id":"s"}]}`))
	}))
	defer server.Close()

	client := workoutclient.NewClient(server.URL, "dev-internal-token")
	ids := make([]string, 250)
	for i := range ids {
		ids[i] = fmt.Sprintf("t%d", i)
	}
	items, err := client.PendingStudents(context.Background(), time.Now(), time.Now().Add(time.Hour), ids)
	if err != nil {
		t.Fatalf("PendingStudents: %v", err)
	}
	if calls != 3 || totalTenants != 250 || len(items) != 3 {
		t.Fatalf("esperava 3 chamadas cobrindo 250 tenants e 3 itens, veio calls=%d tenants=%d itens=%d", calls, totalTenants, len(items))
	}

	calls = 0
	if _, err := client.PendingStudents(context.Background(), time.Now(), time.Now().Add(time.Hour), nil); err != nil {
		t.Fatalf("PendingStudents vazio: %v", err)
	}
	if calls != 0 {
		t.Fatalf("lista vazia não deveria chamar o workout, chamou %d vezes", calls)
	}
}

func TestPendingStudentsRejectsNonOKStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := workoutclient.NewClient(server.URL, "token-errado")
	_, err := client.PendingStudents(context.Background(), time.Now(), time.Now().Add(time.Hour), []string{"t1"})
	if err == nil {
		t.Fatal("status não-200 deveria virar erro")
	}
}
