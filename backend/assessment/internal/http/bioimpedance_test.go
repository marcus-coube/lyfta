package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

type apiBioimpedance struct {
	ID         string   `json:"id"`
	MeasuredAt string   `json:"measured_at"`
	BodyFatPct *float64 `json:"body_fat_pct"`
}

type apiBioimpedanceList struct {
	Items []apiBioimpedance `json:"items"`
}

// TestBioimpedanceEndToEnd espelha o fluxo de medidas: aluno lança, coach lê
// pela ficha, aluno apaga.
func TestBioimpedanceEndToEnd(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student,
		map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 18.4, "bmr_kcal": 1800})
	if rec.Code != http.StatusCreated {
		t.Fatalf("esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}
	var created apiBioimpedance
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decodificar: %v", err)
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/bioimpedance", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var coachView apiBioimpedanceList
	if err := json.Unmarshal(rec.Body.Bytes(), &coachView); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(coachView.Items) != 1 || coachView.Items[0].ID != created.ID {
		t.Fatalf("o coach deveria ver a mesma leitura: %+v", coachView)
	}

	rec = do(t, a.handler, http.MethodDelete, "/v1/me/bioimpedance/"+created.ID, a.student, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("esperava 204, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestBioimpedanceValidation cobre o CHECK de percentuais (0-100).
func TestBioimpedanceValidation(t *testing.T) {
	a := newAssessmentActors(t)

	cases := []struct {
		name string
		body map[string]any
	}{
		{"body_fat_pct acima de 100", map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 150.0}},
		{"body_fat_pct negativo", map[string]any{"measured_at": "2026-08-01", "body_fat_pct": -1.0}},
		{"bmr negativo", map[string]any{"measured_at": "2026-08-01", "bmr_kcal": -100}},
		{"sem data", map[string]any{"body_fat_pct": 20.0}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
			}
		})
	}
}

// TestBioimpedanceIsolation: coach de outro tenant não lê nada.
func TestBioimpedanceIsolation(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student,
		map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 20.0})

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/bioimpedance", a.foreign, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var foreignView apiBioimpedanceList
	if err := json.Unmarshal(rec.Body.Bytes(), &foreignView); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(foreignView.Items) != 0 {
		t.Fatalf("tenant estrangeiro não pode ver bioimpedância de outro tenant: %+v", foreignView.Items)
	}
}
