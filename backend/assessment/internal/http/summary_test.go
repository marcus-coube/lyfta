package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

type apiSummary struct {
	LatestMeasurement *struct {
		WeightKg *float64 `json:"weight_kg"`
		WaistCm  *float64 `json:"waist_cm"`
	} `json:"latest_measurement"`
	LatestBioimpedance *struct {
		BodyFatPct *float64 `json:"body_fat_pct"`
	} `json:"latest_bioimpedance"`
	PhotoCount int `json:"photo_count"`
	Deltas     struct {
		WeightKg   *float64 `json:"weight_kg"`
		BodyFatPct *float64 `json:"body_fat_pct"`
		WaistCm    *float64 `json:"waist_cm"`
	} `json:"deltas"`
	Goal           *string     `json:"goal"`
	ActiveInjuries []apiInjury `json:"active_injuries"`
}

// TestSummaryDeltas cobre o Aceite do P2.3: última medida, última
// bioimpedância, contagem de fotos e deltas vs o registro anterior.
func TestSummaryDeltas(t *testing.T) {
	a := newAssessmentActors(t)

	// Duas medidas: a mais antiga primeiro, para o delta dar negativo (perdeu
	// peso e cintura) na leitura mais recente.
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-07-01", "weight_kg": 85.0, "waist_cm": 95.0})
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 82.0, "waist_cm": 91.5})

	do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student,
		map[string]any{"measured_at": "2026-07-01", "body_fat_pct": 22.0})
	do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student,
		map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 19.5})

	key1 := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/019319b1-0000-7000-8000-000000000001.jpg"
	key2 := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/019319b1-0000-7000-8000-000000000002.jpg"
	do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-07-01", "pose": "front", "media_key": key1})
	do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": key2})

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var summary apiSummary
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decodificar resumo: %v — %s", err, rec.Body.String())
	}

	if summary.LatestMeasurement == nil || summary.LatestMeasurement.WeightKg == nil || *summary.LatestMeasurement.WeightKg != 82.0 {
		t.Fatalf("última medida veio errada: %+v", summary.LatestMeasurement)
	}
	if summary.LatestBioimpedance == nil || summary.LatestBioimpedance.BodyFatPct == nil || *summary.LatestBioimpedance.BodyFatPct != 19.5 {
		t.Fatalf("última bioimpedância veio errada: %+v", summary.LatestBioimpedance)
	}
	if summary.PhotoCount != 2 {
		t.Fatalf("esperava 2 fotos, veio %d", summary.PhotoCount)
	}
	if summary.Deltas.WeightKg == nil || *summary.Deltas.WeightKg != -3.0 {
		t.Fatalf("delta de peso deveria ser -3.0, veio %v", summary.Deltas.WeightKg)
	}
	if summary.Deltas.WaistCm == nil || *summary.Deltas.WaistCm != -3.5 {
		t.Fatalf("delta de cintura deveria ser -3.5, veio %v", summary.Deltas.WaistCm)
	}
	if summary.Deltas.BodyFatPct == nil || *summary.Deltas.BodyFatPct != -2.5 {
		t.Fatalf("delta de %% gordura deveria ser -2.5, veio %v", summary.Deltas.BodyFatPct)
	}
}

// TestSummaryWithoutPreviousHasNoDelta: com um único registro não há
// anterior para comparar — o delta é nulo, não zero (zero seria "não mudou
// nada", nulo é "não dá para saber").
func TestSummaryWithoutPreviousHasNoDelta(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.coach, nil)
	var summary apiSummary
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if summary.Deltas.WeightKg != nil {
		t.Fatalf("sem registro anterior o delta deveria ser nulo, veio %v", *summary.Deltas.WeightKg)
	}
	if summary.PhotoCount != 0 {
		t.Fatalf("esperava 0 fotos, veio %d", summary.PhotoCount)
	}
}

// TestSummaryIsCoachOnly: o aluno não lê o próprio resumo por essa rota (é
// leitura do professor); coach de outro tenant não lê nada.
func TestSummaryIsCoachOnly(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.student, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não deveria ler o resumo: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.foreign, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var summary apiSummary
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if summary.LatestMeasurement != nil || summary.PhotoCount != 0 {
		t.Fatalf("tenant estrangeiro não deveria ver nada: %+v", summary)
	}
}
