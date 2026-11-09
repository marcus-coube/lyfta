package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

// TestHealthDataGateOnMeasurements: medidas e bioimpedância são dado de saúde
// (ADR-008 §1) — sem `health_data` o aluno é barrado nas próprias rotas, o
// coach é barrado nas do aluno e o resumo não traz esses blocos. Fotos têm
// finalidade própria e não passam por este gate.
func TestHealthDataGateOnMeasurements(t *testing.T) {
	a := newAssessmentActors(t)

	// Com consentimento: grava uma medida e uma bioimpedância.
	if rec := do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 82.0}); rec.Code != http.StatusCreated {
		t.Fatalf("medida com consentimento: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", a.student,
		map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 19.5}); rec.Code != http.StatusCreated {
		t.Fatalf("bioimpedância com consentimento: %d %s", rec.Code, rec.Body.String())
	}

	// Aluno sem health_data na claim: toda rota de saúde dele é 403.
	noHealth := signTokenWithConsents(t, a.priv, a.tenantID, a.studentID, []string{"student"}, []string{"terms"})
	for _, rt := range []struct{ method, path string }{
		{http.MethodGet, "/v1/me/measurements"},
		{http.MethodPost, "/v1/me/measurements"},
		{http.MethodGet, "/v1/me/bioimpedance"},
		{http.MethodPost, "/v1/me/bioimpedance"},
	} {
		rec := do(t, a.handler, rt.method, rt.path, noHealth, map[string]any{"measured_at": "2026-08-02", "weight_kg": 80.0})
		if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "consent_required" {
			t.Fatalf("%s %s sem health_data: %d %s", rt.method, rt.path, rec.Code, rec.Body.String())
		}
	}

	// Coach: aluno que revogou o consentimento é barrado e some do resumo.
	a.consents.revoke(a.studentID)
	for _, path := range []string{"/measurements", "/bioimpedance"} {
		rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+path, a.coach, nil)
		if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "consent_required" {
			t.Fatalf("coach em %s sem consentimento do aluno: %d %s", path, rec.Code, rec.Body.String())
		}
	}
	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("resumo sem consentimento: %d %s", rec.Code, rec.Body.String())
	}
	var summary apiSummary
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decodificar resumo: %v", err)
	}
	if summary.LatestMeasurement != nil || summary.LatestBioimpedance != nil || summary.Deltas.WeightKg != nil {
		t.Fatalf("resumo não pode trazer dado de saúde sem consentimento: %s", rec.Body.String())
	}
}
