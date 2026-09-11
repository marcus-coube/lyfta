package workoutclient_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/workoutclient"
)

func TestPendingStudentsHappyPath(t *testing.T) {
	var gotToken, gotSince, gotUntil string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotToken = r.Header.Get("X-Internal-Token")
		gotSince = r.URL.Query().Get("since")
		gotUntil = r.URL.Query().Get("until")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"items":[{"tenant_id":"t1","student_id":"s1"},{"tenant_id":"t1","student_id":"s2"}]}`))
	}))
	defer server.Close()

	client := workoutclient.NewClient(server.URL, "dev-internal-token")
	since := time.Date(2026, 9, 11, 0, 0, 0, 0, time.UTC)
	until := since.AddDate(0, 0, 1)

	items, err := client.PendingStudents(context.Background(), since, until)
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
}

func TestPendingStudentsRejectsNonOKStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := workoutclient.NewClient(server.URL, "token-errado")
	_, err := client.PendingStudents(context.Background(), time.Now(), time.Now().Add(time.Hour))
	if err == nil {
		t.Fatal("status não-200 deveria virar erro")
	}
}
