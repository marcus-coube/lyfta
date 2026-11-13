package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
)

type apiCoachSession struct {
	ClientID        string  `json:"client_id"`
	DayLabel        string  `json:"day_label"`
	PlanTitle       string  `json:"plan_title"`
	FinishedAt      *string `json:"finished_at"`
	DurationSeconds *int    `json:"duration_seconds"`
	SetsCount       int     `json:"sets_count"`
	RepsTotal       int     `json:"reps_total"`
	VolumeKg        float64 `json:"volume_kg"`
	Blocks          []struct {
		BlockType string `json:"block_type"`
		Exercises []struct {
			ExerciseID string `json:"exercise_id"`
			Name       string `json:"name"`
			Sets       []struct {
				SetNo      int `json:"set_no"`
				Prescribed struct {
					RepsMin *int `json:"reps_min"`
					RepsMax *int `json:"reps_max"`
				} `json:"prescribed"`
				Done *struct {
					RepsDone *int     `json:"reps_done"`
					LoadKg   *float64 `json:"load_kg"`
					Revised  bool     `json:"revised"`
				} `json:"done"`
			} `json:"sets"`
		} `json:"exercises"`
	} `json:"blocks"`
}

// TestCoachSessionLookupAndDetail é o Aceite do P11.1: a sessão corrigida
// volta com o valor corrigido e `revised`, série sem log vem com done nulo, o
// lookup ignora o client_id desconhecido e os números batem com o resumo que
// o aluno recebe em /me/today.
func TestCoachSessionLookupAndDetail(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))

	// O plano tem 2 séries por exercício; o aluno faz só a primeira.
	batch := newWorkoutBatch(today.Day.ID, a.exerciseID, 40)
	if rec := do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()); rec.Code != http.StatusOK {
		t.Fatalf("sincronizar: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, map[string]any{
		"events": []map[string]any{{
			"client_id": uuid.NewString(), "type": "set_revision",
			"performed_at": time.Now().UTC().Format(time.RFC3339Nano),
			"payload": map[string]any{
				"session_client_id": batch.sessionClient, "exercise_id": a.exerciseID,
				"set_no": 1, "reps_done": 8, "load_kg": 45, "revises": batch.setClients[0],
			},
		}},
	}); rec.Code != http.StatusOK {
		t.Fatalf("revisão: %d %s", rec.Code, rec.Body.String())
	}

	base := "/v1/students/" + a.studentID + "/sessions"
	var lookup struct {
		Items []apiCoachSession `json:"items"`
	}
	rec := do(t, a.handler, http.MethodPost, base+"/lookup", a.coach, map[string]any{
		"client_ids": []string{batch.sessionClient, batch.sessionClient, uuid.NewString()},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("lookup: %d %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &lookup); err != nil {
		t.Fatalf("decodificar lookup: %v", err)
	}
	if len(lookup.Items) != 1 || lookup.Items[0].ClientID != batch.sessionClient {
		t.Fatalf("o lookup devolve só a sessão que existe: %+v", lookup.Items)
	}
	got := lookup.Items[0]
	if got.DayLabel != "A" || got.PlanTitle == "" || got.SetsCount != 1 || got.RepsTotal != 8 ||
		got.VolumeKg != 360 || got.DurationSeconds == nil || *got.DurationSeconds != 1800 {
		t.Fatalf("métricas da sessão: %+v", got)
	}

	// Mesma definição do resumo do aluno.
	var mine struct {
		RecentSessions []struct {
			TotalSets       int     `json:"total_sets"`
			RepsTotal       int     `json:"reps_total"`
			TotalVolumeKg   float64 `json:"total_volume_kg"`
			DurationSeconds *int    `json:"duration_seconds"`
		} `json:"recent_sessions"`
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil)
	if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil || len(mine.RecentSessions) != 1 {
		t.Fatalf("resumo do aluno: %v %s", err, rec.Body.String())
	}
	m := mine.RecentSessions[0]
	if m.TotalSets != got.SetsCount || m.RepsTotal != got.RepsTotal || m.TotalVolumeKg != got.VolumeKg ||
		m.DurationSeconds == nil || *m.DurationSeconds != *got.DurationSeconds {
		t.Fatalf("aluno e professor divergem: %+v × %+v", m, got)
	}

	var detail apiCoachSession
	rec = do(t, a.handler, http.MethodGet, base+"/"+batch.sessionClient, a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("detalhe: %d %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &detail); err != nil {
		t.Fatalf("decodificar detalhe: %v", err)
	}
	sets := detail.Blocks[0].Exercises[0].Sets
	if detail.Blocks[0].Exercises[0].Name == "" || len(sets) != 2 {
		t.Fatalf("estrutura do snapshot: %+v", detail.Blocks)
	}
	if sets[0].Prescribed.RepsMin == nil || *sets[0].Prescribed.RepsMin != 8 {
		t.Fatalf("prescrito vem do snapshot: %+v", sets[0])
	}
	d := sets[0].Done
	if d == nil || !d.Revised || *d.LoadKg != 45 || *d.RepsDone != 8 {
		t.Fatalf("série corrigida deveria vir com o valor novo e revised: %+v", d)
	}
	if sets[1].Done != nil {
		t.Fatalf("série sem log vem com done nulo: %+v", sets[1].Done)
	}
}

// TestCoachSessionNotFound: sessão inexistente, de outro aluno ou de outro
// tenant é 404 session_not_found; aluno não usa a porta do professor.
func TestCoachSessionNotFound(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	batch := newWorkoutBatch(today.Day.ID, a.exerciseID, 40)
	if rec := do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()); rec.Code != http.StatusOK {
		t.Fatalf("sincronizar: %d %s", rec.Code, rec.Body.String())
	}

	check := func(token, studentID, clientID, who string) {
		t.Helper()
		rec := do(t, a.handler, http.MethodGet, "/v1/students/"+studentID+"/sessions/"+clientID, token, nil)
		if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "session_not_found" {
			t.Errorf("%s: esperava 404 session_not_found, veio %d %s", who, rec.Code, rec.Body.String())
		}
	}
	check(a.coach, a.studentID, uuid.NewString(), "inexistente")
	check(a.coach, a.studentID, "nao-e-uuid", "id inválido")
	check(a.coach, uuid.NewString(), batch.sessionClient, "sessão de outro aluno")
	check(a.foreign, a.studentID, batch.sessionClient, "outro tenant")

	if rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/sessions/"+batch.sessionClient, a.student, nil); rec.Code != http.StatusForbidden {
		t.Errorf("aluno não lê pela porta do professor: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/students/"+a.studentID+"/sessions/lookup", a.coach,
		map[string]any{"client_ids": []string{}}); rec.Code != http.StatusBadRequest {
		t.Errorf("lookup vazio deveria ser 400: %d", rec.Code)
	}
}
