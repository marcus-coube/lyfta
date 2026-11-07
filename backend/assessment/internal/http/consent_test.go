package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
)

// photoKey monta uma key válida na pasta do aluno, como a devolvida pelo presign.
func photoKey(tenantID, studentID string) string {
	return "tenants/" + tenantID + "/students/" + studentID + "/photos/" + uuid.NewString() + ".jpg"
}

// TestStudentWithoutPhotoConsentIsBlocked: aluno sem `progress_photos` nas
// claims leva 403 no presign e no cadastro da foto, mas segue lançando
// medidas (Aceite do P4.5: revogar fotos bloqueia upload).
func TestStudentWithoutPhotoConsentIsBlocked(t *testing.T) {
	a := newAssessmentActors(t)
	noPhotos := signTokenWithConsents(t, a.priv, a.tenantID, a.studentID, []string{"student"}, []string{"terms", "health_data"})

	for _, tc := range []struct {
		name, path string
		body       any
	}{
		{"presign", "/v1/me/media/presign", map[string]any{"content_type": "image/jpeg", "size_bytes": 1024}},
		{"cadastro", "/v1/me/photos", map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": photoKey(a.tenantID, a.studentID)}},
	} {
		rec := do(t, a.handler, http.MethodPost, tc.path, noPhotos, tc.body)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("%s: esperava 403, veio %d %s", tc.name, rec.Code, rec.Body.String())
		}
		if got := decodeError(t, rec); got.Code != "consent_required" || got.Params["purpose"] != "progress_photos" {
			t.Fatalf("%s: erro inesperado %+v", tc.name, got)
		}
	}

	// Revogar fotos não trava o resto do app: medidas continuam.
	rec := do(t, a.handler, http.MethodPost, "/v1/me/measurements", noPhotos,
		map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})
	if rec.Code != http.StatusCreated {
		t.Fatalf("medida sem consentimento de fotos: esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestCoachCannotSeeOrUploadPhotosOfRevokedStudent: sem o consentimento do
// aluno, o coach recebe lista vazia sinalizada, 403 no presign/cadastro e o
// resumo sem contagem de fotos.
func TestCoachCannotSeeOrUploadPhotosOfRevokedStudent(t *testing.T) {
	a := newAssessmentActors(t)

	// Com consentimento a foto existe e o coach a vê.
	rec := do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": photoKey(a.tenantID, a.studentID)})
	if rec.Code != http.StatusCreated {
		t.Fatalf("cadastrar foto: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/photos", a.coach, nil)
	var list apiPhotoList
	_ = json.Unmarshal(rec.Body.Bytes(), &list)
	if rec.Code != http.StatusOK || len(list.Items) != 1 {
		t.Fatalf("coach deveria ver a foto antes da revogação: %d %s", rec.Code, rec.Body.String())
	}

	a.consents.revoke(a.studentID)

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/photos", a.coach, nil)
	var revoked struct {
		Items          []any `json:"items"`
		ConsentRevoked bool  `json:"consent_revoked"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &revoked)
	if rec.Code != http.StatusOK || len(revoked.Items) != 0 || !revoked.ConsentRevoked {
		t.Fatalf("coach não deveria ver fotos de quem revogou: %d %s", rec.Code, rec.Body.String())
	}

	for _, path := range []string{"/media/presign", "/photos"} {
		rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.studentID+path, a.coach,
			map[string]any{"content_type": "image/jpeg", "size_bytes": 10, "taken_at": "2026-08-01", "pose": "front", "media_key": photoKey(a.tenantID, a.studentID)})
		if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "consent_required" {
			t.Fatalf("coach em %s: esperava 403 consent_required, veio %d %s", path, rec.Code, rec.Body.String())
		}
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.coach, nil)
	var summary apiSummary
	_ = json.Unmarshal(rec.Body.Bytes(), &summary)
	if rec.Code != http.StatusOK || summary.PhotoCount != 0 {
		t.Fatalf("resumo sem consentimento deveria zerar a contagem de fotos: %d %s", rec.Code, rec.Body.String())
	}
}

func erase(handler http.Handler, token, userID, tenantID string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, "/internal/v1/users/"+userID+"?tenant_id="+tenantID, nil)
	if token != "" {
		req.Header.Set("X-Internal-Token", token)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

// TestEraseUserDeletesHealthDataAndPhotos cobre o endpoint interno da
// exclusão de conta (P4.5): medidas, bioimpedância e fotos do aluno somem
// (linhas e pasta no storage); o outro aluno e a repetição não mudam nada.
func TestEraseUserDeletesHealthDataAndPhotos(t *testing.T) {
	a := newAssessmentActors(t)
	other := signTokenAs(t, a.priv, a.tenantID, a.otherID, []string{"student"}, time.Now().Add(time.Minute))

	for _, token := range []string{a.student, other} {
		do(t, a.handler, http.MethodPost, "/v1/me/measurements", token, map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})
		do(t, a.handler, http.MethodPost, "/v1/me/bioimpedance", token, map[string]any{"measured_at": "2026-08-01", "body_fat_pct": 20.0})
	}
	do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": photoKey(a.tenantID, a.studentID)})
	do(t, a.handler, http.MethodPost, "/v1/me/photos", other,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": photoKey(a.tenantID, a.otherID)})

	if rec := erase(a.handler, "", a.studentID, a.tenantID); rec.Code != http.StatusUnauthorized {
		t.Fatalf("sem token: esperava 401, veio %d", rec.Code)
	}
	if rec := erase(a.handler, testInternalToken, "nao-e-uuid", a.tenantID); rec.Code != http.StatusBadRequest {
		t.Fatalf("id inválido: esperava 400, veio %d", rec.Code)
	}
	for i := 0; i < 2; i++ { // idempotente
		if rec := erase(a.handler, testInternalToken, a.studentID, a.tenantID); rec.Code != http.StatusNoContent {
			t.Fatalf("tentativa %d: esperava 204, veio %d %s", i+1, rec.Code, rec.Body.String())
		}
	}
	if len(a.objects.deleted) != 2 || a.objects.deleted[0] != a.tenantID+"/"+a.studentID {
		t.Fatalf("a pasta do aluno deveria ter sido apagada do storage: %v", a.objects.deleted)
	}

	for _, resource := range []string{"measurements", "bioimpedance", "photos"} {
		rec := do(t, a.handler, http.MethodGet, "/v1/me/"+resource, a.student, nil)
		var body struct {
			Items []any `json:"items"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if rec.Code != http.StatusOK || len(body.Items) != 0 {
			t.Fatalf("%s do aluno excluído deveria estar vazio: %d %s", resource, rec.Code, rec.Body.String())
		}
		rec = do(t, a.handler, http.MethodGet, "/v1/me/"+resource, other, nil)
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if len(body.Items) != 1 {
			t.Fatalf("%s do outro aluno não pode ser afetado: %s", resource, rec.Body.String())
		}
	}
}

// TestEraseUserStorageFailureKeepsDatabase: storage fora do ar = 500 sem tocar
// o banco, para a repetição refazer tudo (não se perde a pista dos objetos).
func TestEraseUserStorageFailureKeepsDatabase(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPost, "/v1/me/measurements", a.student, map[string]any{"measured_at": "2026-08-01", "weight_kg": 80.0})

	a.objects.fail = true
	if rec := erase(a.handler, testInternalToken, a.studentID, a.tenantID); rec.Code != http.StatusInternalServerError {
		t.Fatalf("storage fora: esperava 500, veio %d", rec.Code)
	}
	rec := do(t, a.handler, http.MethodGet, "/v1/me/measurements", a.student, nil)
	var body struct {
		Items []any `json:"items"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if len(body.Items) != 1 {
		t.Fatalf("o banco não deveria ter sido tocado: %s", rec.Body.String())
	}
}
