package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/coachlink"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

type todayBody struct {
	Date   string         `json:"date"`
	Counts map[string]int `json:"counts"`
	Items  []struct {
		StudentID     string  `json:"student_id"`
		State         string  `json:"state"`
		LastSessionAt *string `json:"last_session_at"`
		Stale         bool    `json:"stale"`
	} `json:"items"`
}

func (b todayBody) stateOf(id string) (string, bool, bool) {
	for _, it := range b.Items {
		if it.StudentID == id {
			return it.State, it.Stale, true
		}
	}
	return "", false, false
}

// TestCoachToday cobre o Aceite da P8.1 no workout: coach vê só o vínculo
// ativo, owner vê todos (com filtro por professor), os quatro estados batem
// com o seed, "hoje" é o dia do fuso da claim e "sem treinar 7+ dias" marca
// quem treinou há mais de 7 dias ou nunca.
func TestCoachToday(t *testing.T) {
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	identity := newFakeIdentity(t)
	handler := newTestRouterWithLinker(t, publicPEM, pool, coachlink.NewClient(identity.server.URL, testInternalToken, 0))

	const tz = "Pacific/Kiritimati" // UTC+14: o "dia" do tenant difere do de UTC
	loc, _ := time.LoadLocation(tz)
	tenant := uuid.NewString()
	coachA, coachB, owner := uuid.NewString(), uuid.NewString(), uuid.NewString()
	trained, inProgress, pending, noPlan, stale, yesterday, inactive, foreign :=
		uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(),
		uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	identity.assign(coachA, trained, inProgress, pending, noPlan, stale, yesterday, inactive)
	identity.assign(coachB, foreign)
	identity.setStatus(inactive, "inactive")
	expires := time.Now().Add(time.Minute)
	tokA := signTokenTZ(t, priv, tenant, coachA, []string{"coach"}, tz, expires)
	tokOwner := signTokenTZ(t, priv, tenant, owner, []string{"owner", "coach"}, tz, expires)
	tokStudent := signTokenTZ(t, priv, tenant, trained, []string{"student"}, tz, expires)

	exerciseID := requireSeededLibrary(t, handler, tokA).ID
	rec := do(t, handler, http.MethodPost, "/v1/plans", tokA, map[string]any{"student_id": trained, "title": "Plano A"})
	planID := decodePlanBody(t, rec.Body.Bytes()).ID
	do(t, handler, http.MethodPut, "/v1/plans/"+planID+"/draft", tokA, draftBody(exerciseID, "A"))
	if rec := do(t, handler, http.MethodPost, "/v1/plans/"+planID+"/publish", tokA, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}

	now := time.Now()
	local := now.In(loc)
	midnight := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	if err := repo.WithTenant(t.Context(), pool, tenant, func(tx pgx.Tx) error {
		// Plano ativo (rotação) para todos menos `noPlan`.
		for _, id := range []string{trained, inProgress, pending, stale, yesterday, inactive, foreign} {
			if _, err := tx.Exec(t.Context(), `
				INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id)
				SELECT $1, $2, v.plan_id, v.id FROM workout_plan_versions v
				WHERE v.plan_id = $3 AND v.published_at IS NOT NULL LIMIT 1
				ON CONFLICT DO NOTHING`, tenant, id, planID); err != nil {
				return err
			}
		}
		session := func(student string, received time.Time, finished bool) error {
			_, err := tx.Exec(t.Context(), `
				INSERT INTO workout_sessions (id, tenant_id, student_id, plan_version_id, day_id, snapshot, client_id, received_at, finished_at)
				SELECT $1, $2, $3, v.id, d.id, '{}'::jsonb, $4, $5, CASE WHEN $6 THEN $5::timestamptz END
				FROM workout_plan_versions v JOIN workout_days d ON d.plan_version_id = v.id
				WHERE v.plan_id = $7 AND v.published_at IS NOT NULL LIMIT 1`,
				uuid.NewString(), tenant, student, uuid.NewString(), received, finished, planID)
			return err
		}
		for _, s := range []struct {
			student  string
			received time.Time
			finished bool
		}{
			{trained, now, true},
			{inProgress, now, false},
			{stale, now.Add(-10 * 24 * time.Hour), true},
			{yesterday, midnight.Add(-time.Minute), true},
			{foreign, now, true},
		} {
			if err := session(s.student, s.received, s.finished); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	get := func(token, query string) (int, todayBody) {
		rec := do(t, handler, http.MethodGet, "/v1/coach/today"+query, token, nil)
		var body todayBody
		if rec.Code == http.StatusOK {
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
		}
		return rec.Code, body
	}

	code, got := get(tokA, "")
	if code != http.StatusOK {
		t.Fatalf("coach: %d", code)
	}
	if got.Date != midnight.Format("2006-01-02") {
		t.Errorf("date: %s, esperava %s (dia no fuso da claim)", got.Date, midnight.Format("2006-01-02"))
	}
	if len(got.Items) != 6 {
		t.Fatalf("coach deveria ver 6 ativos do vínculo (sem inativo nem o aluno de B): %+v", got.Items)
	}
	want := map[string]struct {
		state string
		stale bool
	}{
		trained:    {"trained", false},
		inProgress: {"in_progress", false},
		pending:    {"pending", true}, // nunca treinou
		noPlan:     {"no_plan", true},
		stale:      {"pending", true},  // treinou há 10 dias
		yesterday:  {"pending", false}, // ontem no fuso do tenant: ainda não treinou hoje
	}
	for id, w := range want {
		state, isStale, ok := got.stateOf(id)
		if !ok || state != w.state || isStale != w.stale {
			t.Errorf("aluno %s: estado %q stale=%v (esperava %q stale=%v) ok=%v", id, state, isStale, w.state, w.stale, ok)
		}
	}
	if _, _, ok := got.stateOf(foreign); ok {
		t.Error("coach A não pode ver o aluno de B")
	}
	if _, _, ok := got.stateOf(inactive); ok {
		t.Error("aluno inativo não entra no painel")
	}
	if c := got.Counts; c["trained"] != 1 || c["in_progress"] != 1 || c["pending"] != 3 || c["no_plan"] != 1 || c["stale"] != 3 {
		t.Errorf("contagens: %+v", c)
	}

	// Owner: todos os ativos do tenant (7) e filtro por professor.
	if code, all := get(tokOwner, ""); code != http.StatusOK || len(all.Items) != 7 {
		t.Errorf("owner sem filtro: %d %+v", code, all.Items)
	}
	if code, byB := get(tokOwner, "?coach_id="+coachB); code != http.StatusOK || len(byB.Items) != 1 || byB.Items[0].StudentID != foreign {
		t.Errorf("owner filtrando o professor B: %d %+v", code, byB.Items)
	}
	// Coach puro ignora ?coach_id= (sempre o próprio vínculo).
	if _, own := get(tokA, "?coach_id="+coachB); len(own.Items) != 6 {
		t.Errorf("coach não pode espiar outro professor: %+v", own.Items)
	}
	if code, _ := get(tokOwner, "?coach_id=x"); code != http.StatusBadRequest {
		t.Errorf("coach_id inválido: %d", code)
	}
	if code, _ := get(tokStudent, ""); code != http.StatusForbidden {
		t.Errorf("aluno: esperava 403, veio %d", code)
	}
	if code, _ := get("", ""); code != http.StatusUnauthorized {
		t.Errorf("sem token: %d", code)
	}
	// Identity fora do ar: falha fechada (500), nunca lista vazia.
	identity.setDown(true)
	if code, _ := get(tokA, ""); code != http.StatusInternalServerError {
		t.Errorf("identity fora: %d", code)
	}
}
