package http_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/marcus-coube/lyfta/assessment/internal/media"
)

type apiPresign struct {
	UploadURL string            `json:"upload_url"`
	Method    string            `json:"upload_method"`
	Headers   map[string]string `json:"required_headers"`
	Key       string            `json:"key"`
}

type apiPhoto struct {
	ID        string `json:"id"`
	StudentID string `json:"student_id"`
	TakenAt   string `json:"taken_at"`
	Pose      string `json:"pose"`
	MediaURL  string `json:"media_url"`
}

type apiPhotoList struct {
	Items []apiPhoto `json:"items"`
}

// TestPhotoUploadFlow cobre o Aceite do P2.3 ponta a ponta: o aluno pede a
// URL assinada, cadastra a foto com a key devolvida e o coach enxerga a
// mesma foto pela ficha.
func TestPhotoUploadFlow(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodPost, "/v1/me/media/presign", a.student,
		map[string]any{"content_type": "image/jpeg", "size_bytes": 1024})
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200 no presign, veio %d %s", rec.Code, rec.Body.String())
	}
	var presigned apiPresign
	if err := json.Unmarshal(rec.Body.Bytes(), &presigned); err != nil {
		t.Fatalf("decodificar presign: %v", err)
	}
	if want := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/"; !strings.HasPrefix(presigned.Key, want) {
		t.Fatalf("key fora do layout do P2.3: %q (esperava prefixo %q)", presigned.Key, want)
	}
	if !strings.HasSuffix(presigned.Key, ".jpg") {
		t.Fatalf("esperava extensão .jpg, veio %q", presigned.Key)
	}

	rec = do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": presigned.Key})
	if rec.Code != http.StatusCreated {
		t.Fatalf("esperava 201, veio %d %s", rec.Code, rec.Body.String())
	}
	var created apiPhoto
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decodificar foto: %v", err)
	}
	if created.MediaURL == "" {
		t.Fatal("media_url vazia na resposta")
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/photos", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var coachView apiPhotoList
	if err := json.Unmarshal(rec.Body.Bytes(), &coachView); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(coachView.Items) != 1 || coachView.Items[0].ID != created.ID {
		t.Fatalf("o coach deveria ver a mesma foto: %+v", coachView)
	}

	rec = do(t, a.handler, http.MethodDelete, "/v1/students/"+a.studentID+"/photos/"+created.ID, a.coach, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("esperava 204, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestPresignForStudentByCoach cobre a porta do professor: a key sai da
// mesma pasta do aluno informado na URL, não do coach que fez a chamada.
func TestPresignForStudentByCoach(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodPost, "/v1/students/"+a.studentID+"/media/presign", a.coach,
		map[string]any{"content_type": "image/png", "size_bytes": 2048})
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var presigned apiPresign
	if err := json.Unmarshal(rec.Body.Bytes(), &presigned); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	want := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/"
	if !strings.HasPrefix(presigned.Key, want) || !strings.HasSuffix(presigned.Key, ".png") {
		t.Fatalf("key fora do layout: %q", presigned.Key)
	}
}

// TestPresignRejects cobre tipo fora da whitelist e tamanho acima de 15 MB.
func TestPresignRejects(t *testing.T) {
	a := newAssessmentActors(t)

	cases := []struct {
		name     string
		body     map[string]any
		status   int
		wantCode string
	}{
		{"tipo não permitido", map[string]any{"content_type": "application/pdf", "size_bytes": 1024}, http.StatusUnsupportedMediaType, "unsupported_media_type"},
		{"acima de 15 MB", map[string]any{"content_type": "image/jpeg", "size_bytes": media.MaxUploadBytes + 1}, http.StatusRequestEntityTooLarge, "file_too_large"},
		{"sem tamanho", map[string]any{"content_type": "image/jpeg"}, http.StatusBadRequest, "validation_error"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := do(t, a.handler, http.MethodPost, "/v1/me/media/presign", a.student, tc.body)
			if rec.Code != tc.status {
				t.Fatalf("esperava %d, veio %d %s", tc.status, rec.Code, rec.Body.String())
			}
			if got := decodeError(t, rec).Code; got != tc.wantCode {
				t.Fatalf("esperava code %q, veio %q", tc.wantCode, got)
			}
		})
	}
}

// TestPhotoRejectsForeignMediaKey: uma key fora da pasta do aluno alvo (de
// outro aluno, ou de outro tenant) não é aceita — o par de segurança do
// presign (media.ValidKeyForStudent).
func TestPhotoRejectsForeignMediaKey(t *testing.T) {
	a := newAssessmentActors(t)

	foreignKey := "tenants/" + a.tenantID + "/students/" + a.otherID + "/photos/019319b1-0000-7000-8000-000000000000.jpg"
	rec := do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": foreignKey})
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("esperava 422, veio %d %s", rec.Code, rec.Body.String())
	}
	if got := decodeError(t, rec).Code; got != "invalid_media_key" {
		t.Fatalf("esperava invalid_media_key, veio %q", got)
	}
}

// TestPhotoRejectsInvalidPose cobre o CHECK de pose (front|side|back).
func TestPhotoRejectsInvalidPose(t *testing.T) {
	a := newAssessmentActors(t)
	key := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/019319b1-0000-7000-8000-000000000000.jpg"

	rec := do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "diagonal", "media_key": key})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestPhotoIsolation: aluno não abre a rota do professor, e coach de outro
// tenant não lê nada.
func TestPhotoIsolation(t *testing.T) {
	a := newAssessmentActors(t)
	key := "tenants/" + a.tenantID + "/students/" + a.studentID + "/photos/019319b1-0000-7000-8000-000000000000.jpg"
	do(t, a.handler, http.MethodPost, "/v1/me/photos", a.student,
		map[string]any{"taken_at": "2026-08-01", "pose": "front", "media_key": key})

	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/photos", a.student, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não deveria abrir a rota do professor: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/photos", a.foreign, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("esperava 200, veio %d %s", rec.Code, rec.Body.String())
	}
	var foreignView apiPhotoList
	if err := json.Unmarshal(rec.Body.Bytes(), &foreignView); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if len(foreignView.Items) != 0 {
		t.Fatalf("tenant estrangeiro não pode ver foto de outro tenant: %+v", foreignView.Items)
	}
}
