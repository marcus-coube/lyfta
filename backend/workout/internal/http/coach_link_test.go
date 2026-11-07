package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/coachlink"
)

// fakeIdentity serve o M2M de vínculo (ADR-016 §3) a partir de um mapa
// coach → alunos que o teste muda para simular reatribuição.
type fakeIdentity struct {
	mu       sync.Mutex
	students map[string][]string
	down     bool
	server   *httptest.Server
}

func newFakeIdentity(t *testing.T) *fakeIdentity {
	t.Helper()
	f := &fakeIdentity{students: map[string][]string{}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.down {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		const prefix, suffix = "/internal/v1/coaches/", "/students"
		if r.Header.Get("X-Internal-Token") != testInternalToken ||
			!strings.HasPrefix(r.URL.Path, prefix) || !strings.HasSuffix(r.URL.Path, suffix) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		coach := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, prefix), suffix)
		ids := f.students[coach]
		if ids == nil {
			ids = []string{}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"student_ids": ids})
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeIdentity) assign(coach string, students ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.students[coach] = students
}

func (f *fakeIdentity) setDown(down bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.down = down
}

// TestCoachLinkCrossCoach cobre o Aceite do P4.7 no workout: o coach B recebe
// 404 student_not_found em tudo do aluno de A; o owner acessa tudo; a
// reatribuição troca quem acessa; identity fora do ar fecha o acesso (500).
func TestCoachLinkCrossCoach(t *testing.T) {
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	identity := newFakeIdentity(t)
	// TTL 0: a reatribuição vale na hora; o TTL em si é testado no coachlink.
	handler := newTestRouterWithLinker(t, publicPEM, pool, coachlink.NewClient(identity.server.URL, testInternalToken, 0))

	tenant := uuid.NewString()
	coachA, coachB, owner, student := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	expires := time.Now().Add(time.Minute)
	tokA := signTokenAs(t, priv, tenant, coachA, []string{"coach"}, expires)
	tokB := signTokenAs(t, priv, tenant, coachB, []string{"coach"}, expires)
	tokOwner := signTokenAs(t, priv, tenant, owner, []string{"owner", "coach"}, expires)
	identity.assign(coachA, student)

	exerciseID := requireSeededLibrary(t, handler, tokA).ID

	// A cria, edita e publica o plano do aluno dele.
	rec := do(t, handler, http.MethodPost, "/v1/plans", tokA, map[string]any{"student_id": student, "title": "Plano A"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("A cria plano do próprio aluno: %d %s", rec.Code, rec.Body.String())
	}
	planID := decodePlanBody(t, rec.Body.Bytes()).ID
	if rec := do(t, handler, http.MethodPut, "/v1/plans/"+planID+"/draft", tokA, draftBody(exerciseID, "A")); rec.Code != http.StatusOK {
		t.Fatalf("A edita: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, handler, http.MethodPost, "/v1/plans/"+planID+"/publish", tokA, nil); rec.Code != http.StatusOK {
		t.Fatalf("A publica: %d %s", rec.Code, rec.Body.String())
	}

	studentURL := "/v1/students/" + student
	type call struct {
		method, path string
		body         any
	}
	blocked := []call{
		{http.MethodPost, "/v1/plans", map[string]any{"student_id": student, "title": "Invasão"}},
		{http.MethodGet, "/v1/plans/" + planID, nil},
		{http.MethodPut, "/v1/plans/" + planID + "/draft", draftBody(exerciseID, "A")},
		{http.MethodPost, "/v1/plans/" + planID + "/publish", nil},
		{http.MethodGet, studentURL + "/plans", nil},
		{http.MethodGet, studentURL + "/exercises/logged", nil},
		{http.MethodGet, studentURL + "/exercises/" + exerciseID + "/history", nil},
		{http.MethodPost, "/v1/me/plan/override-day", map[string]any{"student_id": student, "day_id": uuid.NewString()}},
	}
	assertBlocked := func(token, who string) {
		t.Helper()
		for _, c := range blocked {
			rec := do(t, handler, c.method, c.path, token, c.body)
			if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
				t.Errorf("%s: %s %s deveria ser 404 student_not_found, veio %d %s", who, c.method, c.path, rec.Code, rec.Body.String())
			}
		}
	}
	assertBlocked(tokB, "coach B")

	// O owner acessa sem vínculo.
	for _, path := range []string{"/v1/plans/" + planID, studentURL + "/plans", studentURL + "/exercises/logged"} {
		if rec := do(t, handler, http.MethodGet, path, tokOwner, nil); rec.Code != http.StatusOK {
			t.Errorf("owner: GET %s: %d %s", path, rec.Code, rec.Body.String())
		}
	}

	// Plano atribuído a outro coach: o coach_id do owner precisa ser o vinculado.
	body := map[string]any{"student_id": student, "title": "Do owner", "coach_id": coachB}
	if rec := do(t, handler, http.MethodPost, "/v1/plans", tokOwner, body); rec.Code != http.StatusBadRequest {
		t.Errorf("owner com coach_id não vinculado: esperava 400, veio %d %s", rec.Code, rec.Body.String())
	}
	body["coach_id"] = coachA
	if rec := do(t, handler, http.MethodPost, "/v1/plans", tokOwner, body); rec.Code != http.StatusCreated {
		t.Errorf("owner com coach_id vinculado: esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}

	// Reatribuição: B passa a acessar (e edita, mesmo não sendo o autor do
	// plano) e A perde.
	identity.assign(coachA)
	identity.assign(coachB, student)
	if rec := do(t, handler, http.MethodPut, "/v1/plans/"+planID+"/draft", tokB, draftBody(exerciseID, "A", "B")); rec.Code != http.StatusOK {
		t.Errorf("B reatribuído deveria editar: %d %s", rec.Code, rec.Body.String())
	}
	assertBlocked(tokA, "antigo coach A")

	// Identity fora do ar: o acesso do coach fecha com 500; o owner não depende.
	identity.setDown(true)
	if rec := do(t, handler, http.MethodGet, studentURL+"/plans", tokB, nil); rec.Code != http.StatusInternalServerError {
		t.Errorf("identity fora: esperava 500, veio %d", rec.Code)
	}
	if rec := do(t, handler, http.MethodGet, studentURL+"/plans", tokOwner, nil); rec.Code != http.StatusOK {
		t.Errorf("owner não depende do identity: %d", rec.Code)
	}
}
