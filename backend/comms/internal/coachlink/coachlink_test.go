package coachlink

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func fakeIdentity(t *testing.T, calls *atomic.Int32, body string, status int) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Header.Get("X-Internal-Token") != "segredo" || r.URL.Path != "/internal/v1/coaches/coach-1/students" || r.URL.Query().Get("tenant_id") != "t-1" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestStudentsOfCachesWithinTTLAndRefreshesAfter(t *testing.T) {
	var calls atomic.Int32
	srv := fakeIdentity(t, &calls, `{"student_ids":["s-1","s-2"]}`, http.StatusOK)
	c := NewClient(srv.URL, "segredo", 30*time.Second)
	clock := time.Now()
	c.now = func() time.Time { return clock }
	ctx := context.Background()

	set, err := c.StudentsOf(ctx, "t-1", "coach-1")
	if err != nil || len(set) != 2 {
		t.Fatalf("StudentsOf: %v %v", set, err)
	}
	if _, err := c.StudentsOf(ctx, "t-1", "coach-1"); err != nil || calls.Load() != 1 {
		t.Fatalf("segunda chamada deveria vir do cache: calls=%d err=%v", calls.Load(), err)
	}

	clock = clock.Add(29 * time.Second)
	_, _ = c.StudentsOf(ctx, "t-1", "coach-1")
	if calls.Load() != 1 {
		t.Fatalf("aos 29s ainda vale o cache: calls=%d", calls.Load())
	}
	clock = clock.Add(2 * time.Second)
	_, _ = c.StudentsOf(ctx, "t-1", "coach-1")
	if calls.Load() != 2 {
		t.Fatalf("passado o TTL deveria consultar de novo: calls=%d", calls.Load())
	}
}

func TestStudentsOfIdentityDownIsErrorAndNotCached(t *testing.T) {
	var calls atomic.Int32
	srv := fakeIdentity(t, &calls, `{}`, http.StatusInternalServerError)
	c := NewClient(srv.URL, "segredo", 30*time.Second)
	ctx := context.Background()

	if _, err := c.StudentsOf(ctx, "t-1", "coach-1"); err == nil {
		t.Fatal("identity com 500 deveria virar erro")
	}
	if _, err := c.StudentsOf(ctx, "t-1", "coach-1"); err == nil || calls.Load() != 2 {
		t.Fatalf("falha não pode ser cacheada: calls=%d err=%v", calls.Load(), err)
	}

	srv.Close()
	if _, err := c.StudentsOf(ctx, "t-1", "coach-1"); err == nil {
		t.Fatal("identity fora do ar deveria virar erro")
	}
}

func TestCanAccessStudent(t *testing.T) {
	var calls atomic.Int32
	srv := fakeIdentity(t, &calls, `{"student_ids":["s-1"]}`, http.StatusOK)
	c := NewClient(srv.URL, "segredo", 30*time.Second)
	ctx := context.Background()

	// Owner na claim libera sem chamar o identity.
	if ok, err := c.CanAccessStudent(ctx, "t-1", "owner-1", []string{"owner", "coach"}, "qualquer"); err != nil || !ok {
		t.Fatalf("owner: ok=%v err=%v", ok, err)
	}
	if calls.Load() != 0 {
		t.Fatalf("owner não deve gerar chamada: %d", calls.Load())
	}
	if ok, err := c.CanAccessStudent(ctx, "t-1", "coach-1", []string{"coach"}, "s-1"); err != nil || !ok {
		t.Fatalf("aluno vinculado: ok=%v err=%v", ok, err)
	}
	if ok, err := c.CanAccessStudent(ctx, "t-1", "coach-1", []string{"coach"}, "s-9"); err != nil || ok {
		t.Fatalf("aluno de outro coach: ok=%v err=%v", ok, err)
	}
}

func TestZeroTTLDisablesCache(t *testing.T) {
	var calls atomic.Int32
	srv := fakeIdentity(t, &calls, `{"student_ids":[]}`, http.StatusOK)
	c := NewClient(srv.URL, "segredo", 0)
	_, _ = c.StudentsOf(context.Background(), "t-1", "coach-1")
	_, _ = c.StudentsOf(context.Background(), "t-1", "coach-1")
	if calls.Load() != 2 {
		t.Fatalf("sem cache, 2 chamadas: %d", calls.Load())
	}
}

func TestCoachOf(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Internal-Token") != "segredo" || r.URL.Query().Get("tenant_id") != "t-1" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		switch r.URL.Path {
		case "/internal/v1/students/s-1/coach":
			_, _ = w.Write([]byte(`{"coach_id":"coach-1"}`))
		case "/internal/v1/students/s-sem/coach":
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"code":"student_not_found"}`))
		default:
			w.WriteHeader(http.StatusInternalServerError)
		}
	}))
	defer srv.Close()
	c := NewClient(srv.URL, "segredo", 30*time.Second)
	ctx := context.Background()

	if id, found, err := c.CoachOf(ctx, "t-1", "s-1"); err != nil || !found || id != "coach-1" {
		t.Fatalf("CoachOf vinculado: %q %v %v", id, found, err)
	}
	if _, found, err := c.CoachOf(ctx, "t-1", "s-sem"); err != nil || found {
		t.Fatalf("aluno sem vínculo: found=%v err=%v", found, err)
	}
	if _, _, err := c.CoachOf(ctx, "t-1", "s-erro"); err == nil {
		t.Fatal("identity com 500 deveria virar erro")
	}
}
