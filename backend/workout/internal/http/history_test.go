package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
)

// apiHistory espelha a série temporal como o app do aluno vai lê-la.
type apiHistory struct {
	ExerciseID string `json:"exercise_id"`
	Items      []struct {
		SessionID     string   `json:"session_id"`
		PerformedAt   string   `json:"performed_at"`
		Sets          int      `json:"sets"`
		MaxLoadKg     *float64 `json:"max_load_kg"`
		TotalVolumeKg float64  `json:"total_volume_kg"`
		TopSet        struct {
			SetNo    int      `json:"set_no"`
			RepsDone *int     `json:"reps_done"`
			LoadKg   *float64 `json:"load_kg"`
		} `json:"top_set"`
	} `json:"items"`
	NextCursor string `json:"next_cursor"`
}

type apiLogged struct {
	Items []struct {
		Sessions        int    `json:"sessions"`
		LastPerformedAt string `json:"last_performed_at"`
		Exercise        *struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"exercise"`
	} `json:"items"`
}

func decodeHistory(t *testing.T, rec *httptest.ResponseRecorder) apiHistory {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 no histórico, veio %d %s", rec.Code, rec.Body.String())
	}
	var out apiHistory
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("decodificar histórico: %v — %s", err, rec.Body.String())
	}
	return out
}

// TestExerciseHistoryEndToEnd: o aluno treina duas vezes e as duas portas —
// a dele e a do professor — enxergam a mesma série.
func TestExerciseHistoryEndToEnd(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)

	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	dayA := today.Day.ID
	for _, loads := range [][]float64{{40, 42.5}, {45, 47.5}} {
		batch := newWorkoutBatch(dayA, a.exerciseID, loads...)
		if rec := do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()); rec.Code != http.StatusOK {
			t.Fatalf("sincronizar treino: %d %s", rec.Code, rec.Body.String())
		}
		// Voltar para o A: a rotação avançou para o B ao fechar a sessão.
		if rec := do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student,
			map[string]any{"day_id": dayA}); rec.Code != http.StatusOK {
			t.Fatalf("voltar ao dia A: %d %s", rec.Code, rec.Body.String())
		}
	}

	path := "/v1/me/exercises/" + a.exerciseID + "/history"
	hist := decodeHistory(t, do(t, a.handler, http.MethodGet, path, a.student, nil))
	if hist.ExerciseID != a.exerciseID || len(hist.Items) != 2 {
		t.Fatalf("esperava 2 pontos para o exercício: %+v", hist)
	}
	recent := hist.Items[0]
	if recent.Sets != 2 || recent.MaxLoadKg == nil || *recent.MaxLoadKg != 47.5 {
		t.Fatalf("ponto mais recente veio errado: %+v", recent)
	}
	if want := (45 + 47.5) * 10.0; recent.TotalVolumeKg != want {
		t.Fatalf("volume deveria ser %v, veio %v", want, recent.TotalVolumeKg)
	}
	if recent.TopSet.SetNo != 2 || recent.TopSet.LoadKg == nil || *recent.TopSet.LoadKg != 47.5 {
		t.Fatalf("top set veio errado: %+v", recent.TopSet)
	}
	if hist.NextCursor != "" {
		t.Fatalf("duas sessões cabem numa página, não deveria haver cursor: %q", hist.NextCursor)
	}

	// A mesma série pela porta do professor.
	coachPath := "/v1/students/" + a.studentID + "/exercises/" + a.exerciseID + "/history"
	coachHist := decodeHistory(t, do(t, a.handler, http.MethodGet, coachPath, a.coach, nil))
	if len(coachHist.Items) != len(hist.Items) || coachHist.Items[0].SessionID != recent.SessionID {
		t.Fatalf("o professor deveria ver a mesma série: %+v", coachHist)
	}

	// Índice da tela Evolução: o exercício treinado, com nome resolvido.
	var logged apiLogged
	rec := do(t, a.handler, http.MethodGet, "/v1/me/exercises/logged", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("índice: %d %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &logged); err != nil {
		t.Fatalf("decodificar índice: %v", err)
	}
	if len(logged.Items) != 1 || logged.Items[0].Sessions != 2 {
		t.Fatalf("índice deveria trazer 1 exercício com 2 sessões: %+v", logged.Items)
	}
	if logged.Items[0].Exercise == nil || logged.Items[0].Exercise.ID != a.exerciseID ||
		logged.Items[0].Exercise.Name == "" {
		t.Fatalf("o índice precisa do exercício resolvido para desenhar o seletor: %+v", logged.Items[0])
	}
}

// TestHistoryIsolation: aluno não abre a porta do professor, e professor de
// outro tenant não lê nada — a rota do aluno nem tem parâmetro de aluno.
func TestHistoryIsolation(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)

	path := "/v1/students/" + a.studentID + "/exercises/" + a.exerciseID + "/history"
	if rec := do(t, a.handler, http.MethodGet, path, a.student, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não lê pela rota do professor: %d %s", rec.Code, rec.Body.String())
	}
	// Tenant estrangeiro: o exercício é da biblioteca global, mas o aluno não
	// é dele — a RLS corta o histórico e sobra lista vazia.
	rec := do(t, a.handler, http.MethodGet, path, a.foreign, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 vazio para tenant estrangeiro, veio %d %s", rec.Code, rec.Body.String())
	}
	var hist apiHistory
	if err := json.Unmarshal(rec.Body.Bytes(), &hist); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(hist.Items) != 0 {
		t.Fatalf("tenant estrangeiro não pode ver execução de outro tenant: %+v", hist.Items)
	}
}

// TestHistoryRejectsUnknownExercise: id fora da biblioteca do tenant é 404, e
// id malformado é erro de validação — sem isso a tela não distingue "id
// errado" de "ainda não treinou".
func TestHistoryRejectsUnknownExercise(t *testing.T) {
	a := builderFixture(t)

	rec := do(t, a.handler, http.MethodGet, "/v1/me/exercises/"+uuid.NewString()+"/history", a.student, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("exercício inexistente deveria dar 404, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/me/exercises/nao-e-uuid/history", a.student, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("id malformado deveria dar 400, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/me/exercises/"+a.exerciseID+"/history?cursor=nao-e-cursor", a.student, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("cursor inválido deveria dar 400, veio %d %s", rec.Code, rec.Body.String())
	}
}
