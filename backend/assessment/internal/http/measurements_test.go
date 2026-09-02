package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

type apiMeasurement struct {
	ID         string   `json:"id"`
	StudentID  string   `json:"student_id"`
	MeasuredAt string   `json:"measured_at"`
	WeightKg   *float64 `json:"weight_kg"`
	WaistCm    *float64 `json:"waist_cm"`
}

type apiMeasurementList struct {
	Items      []apiMeasurement `json:"items"`
	NextCursor string           `json:"next_cursor"`
}

// TestMeasurementCreatedByStudentEndToEnd: o aluno lança a própria medida
// pela porta /me, e o coach do tenant enxerga o mesmo registro pela porta
// /students/{id} — mesma leitura, duas portas (P2.1/P2.3).
func TestMeasurementCreatedByStudentEndToEnd(t *testing.T) {
	a := newAssessmentActors(t)

	body := map[string]any{"measured_at": "2026-08-01", "weight_kg": 82.5, "waist_cm": 91.0}
	rec := do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student, body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}
	var created apiMeasurement
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if created.WeightKg == nil || *created.WeightKg != 82.5 {
		t.Fatalf("weight_kg veio errado: %+v", created)
	}

	// O aluno lê a própria lista.
	rec = do(t, a.handler, http.MethodGet, "/v1/me/measurements", a.student, nil)
	var mine apiMeasurementList
	if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil {
		t.Fatalf("decodificar lista do aluno: %v", err)
	}
	if len(mine.Items) != 1 || mine.Items[0].ID != created.ID {
		t.Fatalf("lista do aluno veio errada: %+v", mine)
	}

	// O coach do tenant lê a mesma medida pela porta do professor.
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/measurements", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 para o coach, veio %d %s", rec.Code, rec.Body.String())
	}
	var coachView apiMeasurementList
	if err := json.Unmarshal(rec.Body.Bytes(), &coachView); err != nil {
		t.Fatalf("decodificar lista do coach: %v", err)
	}
	if len(coachView.Items) != 1 || coachView.Items[0].ID != created.ID {
		t.Fatalf("o coach deveria ver a mesma medida: %+v", coachView)
	}

	// O aluno apaga a própria medida.
	rec = do(t, a.handler, http.MethodDelete, "/v1/me/measurements/"+created.ID, a.student, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("esperava 204 ao apagar, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/me/measurements", a.student, nil)
	if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil {
		t.Fatalf("decodificar lista após apagar: %v", err)
	}
	if len(mine.Items) != 0 {
		t.Fatalf("esperava lista vazia após apagar, veio %+v", mine.Items)
	}
}

// TestCoachLaunchesForStudent cobre o outro sentido: o coach lança uma medida
// pela ficha do aluno (avaliação presencial) e o aluno vê o próprio registro.
func TestCoachLaunchesForStudent(t *testing.T) {
	a := newAssessmentActors(t)

	body := map[string]any{"measured_at": "2026-08-10", "weight_kg": 75.0}
	rec := do(t, a.handler, http.MethodPost, "/v1/students/"+a.studentID+"/measurements", a.coach, body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/me/measurements", a.student, nil)
	var mine apiMeasurementList
	if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(mine.Items) != 1 {
		t.Fatalf("o aluno deveria ver a medida lançada pelo coach: %+v", mine)
	}
}

// TestMeasurementPermissionIsolation cobre o Aceite da P2.3: o aluno não abre
// a porta do professor (403), e um coach de outro tenant não lê nada — a
// RLS corta a lista antes de qualquer JOIN por student_id.
func TestMeasurementPermissionIsolation(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})

	// Aluno tentando a rota do professor.
	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/measurements", a.student, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não deveria abrir a rota do professor: %d %s", rec.Code, rec.Body.String())
	}

	// Coach de outro tenant: a RLS filtra antes do WHERE student_id, então a
	// lista vem vazia (não 403 — o tenant simplesmente não vê o registro).
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/measurements", a.foreign, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 vazio para tenant estrangeiro, veio %d %s", rec.Code, rec.Body.String())
	}
	var foreignView apiMeasurementList
	if err := json.Unmarshal(rec.Body.Bytes(), &foreignView); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(foreignView.Items) != 0 {
		t.Fatalf("tenant estrangeiro não pode ver medida de outro tenant: %+v", foreignView.Items)
	}
}

// TestMeasurementStudentIsolation: dois alunos do mesmo tenant não veem a
// medida um do outro — o coach lendo a ficha de um não traz o que pertence
// ao outro.
func TestMeasurementStudentIsolation(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.otherID+"/measurements", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var other apiMeasurementList
	if err := json.Unmarshal(rec.Body.Bytes(), &other); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(other.Items) != 0 {
		t.Fatalf("aluno B não deveria ver a medida do aluno A: %+v", other.Items)
	}
}

// TestMeasurementValidation cobre os casos de erro: data ausente/malformada e
// peso fora do CHECK (> 0) — devolvidos como validation_error traduzível em
// vez de erro de constraint do banco.
func TestMeasurementValidation(t *testing.T) {
	a := newAssessmentActors(t)

	cases := []struct {
		name string
		body map[string]any
	}{
		{"sem data", map[string]any{"weight_kg": 80.0}},
		{"data malformada", map[string]any{"measured_at": "01/08/2026"}},
		{"peso negativo", map[string]any{"measured_at": "2026-08-01", "weight_kg": -1.0}},
		{"peso zero", map[string]any{"measured_at": "2026-08-01", "weight_kg": 0.0}},
		{"cintura negativa", map[string]any{"measured_at": "2026-08-01", "waist_cm": -5.0}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
			}
			if got := decodeError(t, rec).Code; got != "validation_error" {
				t.Fatalf("esperava validation_error, veio %q", got)
			}
		})
	}
}

// TestMeasurementDeleteNotFound cobre apagar um id inexistente e um id
// malformado.
func TestMeasurementDeleteNotFound(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodDelete, "/v1/me/measurements/019319b1-0000-7000-8000-000000000000", a.student, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("esperava 404, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodDelete, "/v1/me/measurements/nao-e-uuid", a.student, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
	}
}
