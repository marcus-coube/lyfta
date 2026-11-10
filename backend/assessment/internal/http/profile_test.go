package http_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

type apiProfile struct {
	Goal               *string `json:"goal"`
	GoalNotes          string  `json:"goal_notes"`
	TrainingExperience *string `json:"training_experience"`
	WeeklyTarget       *int    `json:"weekly_target"`
	MedicalNotes       string  `json:"medical_notes"`
	CoachNotes         *string `json:"coach_notes"`
}

type apiInjury struct {
	ID         string  `json:"id"`
	BodyRegion string  `json:"body_region"`
	ResolvedAt *string `json:"resolved_at"`
	Active     bool    `json:"active"`
}

type apiInjuryList struct {
	Items []apiInjury `json:"items"`
}

func decode[T any](t *testing.T, body []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(body, &v); err != nil {
		t.Fatalf("decodificar %s: %v", body, err)
	}
	return v
}

// TestStudentNeverSeesCoachNotes é o Aceite central do P5.3: o coach grava
// coach_notes, o aluno lê o mesmo perfil sem o campo (nem a chave) e não
// consegue sobrescrevê-lo pela própria porta.
func TestStudentNeverSeesCoachNotes(t *testing.T) {
	a := newAssessmentActors(t)
	base := "/v1/students/" + a.studentID + "/profile"

	rec := do(t, a.handler, http.MethodPut, base, a.coach, map[string]any{
		"goal": "hypertrophy", "training_experience": "intermediate", "weekly_target": 4,
		"medical_notes": "hipertensão controlada", "coach_notes": "tende a faltar às segundas",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("coach deveria gravar: %d %s", rec.Code, rec.Body.String())
	}
	if p := decode[apiProfile](t, rec.Body.Bytes()); p.CoachNotes == nil || *p.CoachNotes != "tende a faltar às segundas" {
		t.Fatalf("coach deveria ver coach_notes: %s", rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/me/profile", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("aluno deveria ler: %d %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "coach_notes") || strings.Contains(rec.Body.String(), "segundas") {
		t.Fatalf("aluno não pode ver coach_notes: %s", rec.Body.String())
	}
	if p := decode[apiProfile](t, rec.Body.Bytes()); p.Goal == nil || *p.Goal != "hypertrophy" || p.MedicalNotes != "hipertensão controlada" {
		t.Fatalf("aluno deveria ver o resto do perfil: %s", rec.Body.String())
	}

	// O aluno edita os próprios campos e tenta (em vão) escrever coach_notes.
	rec = do(t, a.handler, http.MethodPut, "/v1/me/profile", a.student, map[string]any{
		"goal": "strength", "weekly_target": 3, "coach_notes": "invadido",
	})
	if rec.Code != http.StatusOK || strings.Contains(rec.Body.String(), "coach_notes") {
		t.Fatalf("PUT do aluno: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodGet, base, a.coach, nil)
	p := decode[apiProfile](t, rec.Body.Bytes())
	if p.Goal == nil || *p.Goal != "strength" || p.CoachNotes == nil || *p.CoachNotes != "tende a faltar às segundas" {
		t.Fatalf("a edição do aluno não pode apagar coach_notes: %s", rec.Body.String())
	}
	// A meta semanal (streak) é do coach: o 3 do aluno é ignorado.
	if p.WeeklyTarget == nil || *p.WeeklyTarget != 4 {
		t.Fatalf("o aluno não pode mudar a meta semanal: %s", rec.Body.String())
	}
}

// TestStudentFirstProfileHasNoWeeklyTarget: o primeiro PUT do aluno cria o
// perfil sem meta semanal, mesmo que ele mande uma.
func TestStudentFirstProfileHasNoWeeklyTarget(t *testing.T) {
	a := newAssessmentActors(t)
	rec := do(t, a.handler, http.MethodPut, "/v1/me/profile", a.student, map[string]any{
		"goal": "health", "weekly_target": 6,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("PUT do aluno: %d %s", rec.Code, rec.Body.String())
	}
	if p := decode[apiProfile](t, rec.Body.Bytes()); p.WeeklyTarget != nil || p.Goal == nil || *p.Goal != "health" {
		t.Fatalf("perfil criado pelo aluno não pode ter meta semanal: %s", rec.Body.String())
	}
}

func TestProfileEmptyAndValidation(t *testing.T) {
	a := newAssessmentActors(t)

	rec := do(t, a.handler, http.MethodGet, "/v1/me/profile", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("perfil inexistente deveria vir vazio: %d %s", rec.Code, rec.Body.String())
	}
	if p := decode[apiProfile](t, rec.Body.Bytes()); p.Goal != nil || p.WeeklyTarget != nil {
		t.Fatalf("esperava perfil vazio: %s", rec.Body.String())
	}

	for name, body := range map[string]map[string]any{
		"goal":          {"goal": "ficar_gigante"},
		"weekly_target": {"weekly_target": 8},
		"experience":    {"training_experience": "pro"},
	} {
		rec = do(t, a.handler, http.MethodPut, "/v1/me/profile", a.student, body)
		if rec.Code != http.StatusBadRequest || decodeError(t, rec).Code != "validation_error" {
			t.Fatalf("%s: esperava validation_error, veio %d %s", name, rec.Code, rec.Body.String())
		}
	}
}

// TestInjuryResolvedLeavesActiveSummary: lesão resolvida sai do resumo de
// ativas; reabrir (resolved_at null) a traz de volta; o resumo carrega o
// objetivo.
func TestInjuryResolvedLeavesActiveSummary(t *testing.T) {
	a := newAssessmentActors(t)
	do(t, a.handler, http.MethodPut, "/v1/me/profile", a.student, map[string]any{"goal": "rehab"})

	rec := do(t, a.handler, http.MethodPost, "/v1/me/injuries", a.student,
		map[string]any{"body_region": "knee", "description": "condromalácia", "since": "2026-01-10"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar lesão: %d %s", rec.Code, rec.Body.String())
	}
	knee := decode[apiInjury](t, rec.Body.Bytes())
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.studentID+"/injuries", a.coach,
		map[string]any{"body_region": "lower_back", "description": "hérnia L5"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("coach cria lesão: %d %s", rec.Code, rec.Body.String())
	}

	summary := func() apiSummary {
		rec := do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/summary", a.coach, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("resumo: %d %s", rec.Code, rec.Body.String())
		}
		return decode[apiSummary](t, rec.Body.Bytes())
	}
	s := summary()
	if s.Goal == nil || *s.Goal != "rehab" || len(s.ActiveInjuries) != 2 {
		t.Fatalf("resumo deveria ter objetivo e 2 ativas: %+v", s)
	}

	rec = do(t, a.handler, http.MethodPatch, "/v1/me/injuries/"+knee.ID, a.student,
		map[string]any{"resolved_at": "2026-06-01"})
	if rec.Code != http.StatusOK || decode[apiInjury](t, rec.Body.Bytes()).Active {
		t.Fatalf("resolver: %d %s", rec.Code, rec.Body.String())
	}
	if s = summary(); len(s.ActiveInjuries) != 1 || s.ActiveInjuries[0].BodyRegion != "lower_back" {
		t.Fatalf("resolvida deveria sair das ativas: %+v", s.ActiveInjuries)
	}

	// A lista completa mantém a resolvida, depois das ativas.
	list := decode[apiInjuryList](t, do(t, a.handler, http.MethodGet, "/v1/me/injuries", a.student, nil).Body.Bytes())
	if len(list.Items) != 2 || list.Items[1].ID != knee.ID {
		t.Fatalf("lista completa errada: %+v", list.Items)
	}
	list = decode[apiInjuryList](t, do(t, a.handler, http.MethodGet, "/v1/me/injuries?active=true", a.student, nil).Body.Bytes())
	if len(list.Items) != 1 {
		t.Fatalf("active=true deveria filtrar: %+v", list.Items)
	}

	// Reabrir.
	rec = do(t, a.handler, http.MethodPatch, "/v1/me/injuries/"+knee.ID, a.student, map[string]any{"resolved_at": nil})
	if rec.Code != http.StatusOK || !decode[apiInjury](t, rec.Body.Bytes()).Active {
		t.Fatalf("reabrir: %d %s", rec.Code, rec.Body.String())
	}
	if s = summary(); len(s.ActiveInjuries) != 2 {
		t.Fatalf("reaberta deveria voltar: %+v", s.ActiveInjuries)
	}

	rec = do(t, a.handler, http.MethodDelete, "/v1/me/injuries/"+knee.ID, a.student, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("apagar: %d", rec.Code)
	}
	rec = do(t, a.handler, http.MethodDelete, "/v1/me/injuries/"+knee.ID, a.student, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("apagar de novo deveria ser 404: %d", rec.Code)
	}
}

func TestInjuryValidationAndOwnership(t *testing.T) {
	a := newAssessmentActors(t)

	for name, body := range map[string]map[string]any{
		"região":    {"body_region": "cotovelo", "description": "x"},
		"descrição": {"body_region": "knee", "description": "  "},
		"datas":     {"body_region": "knee", "description": "x", "since": "2026-05-01", "resolved_at": "2026-04-01"},
		"data":      {"body_region": "knee", "description": "x", "since": "ontem"},
	} {
		rec := do(t, a.handler, http.MethodPost, "/v1/me/injuries", a.student, body)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s: esperava 400, veio %d %s", name, rec.Code, rec.Body.String())
		}
	}

	// Lesão do aluno não é acessível por outro aluno do tenant.
	rec := do(t, a.handler, http.MethodPost, "/v1/me/injuries", a.student, map[string]any{"body_region": "knee", "description": "x"})
	id := decode[apiInjury](t, rec.Body.Bytes()).ID
	other := signTokenAs(t, a.priv, a.tenantID, a.otherID, []string{"student"}, time.Now().Add(time.Minute))
	rec = do(t, a.handler, http.MethodPatch, "/v1/me/injuries/"+id, other, map[string]any{"description": "y"})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("outro aluno deveria receber 404: %d %s", rec.Code, rec.Body.String())
	}
	// PATCH inválido não grava nada.
	rec = do(t, a.handler, http.MethodPatch, "/v1/me/injuries/"+id, a.student, map[string]any{"description": "novo", "body_region": "xx"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("patch inválido: %d", rec.Code)
	}
	list := decode[apiInjuryList](t, do(t, a.handler, http.MethodGet, "/v1/me/injuries", a.student, nil).Body.Bytes())
	if len(list.Items) != 1 || list.Items[0].BodyRegion != "knee" {
		t.Fatalf("patch inválido não pode gravar: %+v", list.Items)
	}
}

// TestProfileGates: aluno sem health_data na claim é barrado; o aluno não usa
// as portas do coach; o coach de outro tenant não vê nada do aluno.
func TestProfileGates(t *testing.T) {
	a := newAssessmentActors(t)

	noHealth := signTokenWithConsents(t, a.priv, a.tenantID, a.studentID, []string{"student"}, []string{"terms"})
	rec := do(t, a.handler, http.MethodGet, "/v1/me/profile", noHealth, nil)
	if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "consent_required" {
		t.Fatalf("sem health_data: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/profile", a.student, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno na porta do coach: %d", rec.Code)
	}

	do(t, a.handler, http.MethodPut, "/v1/me/profile", a.student, map[string]any{"goal": "health"})
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/profile", a.foreign, nil)
	if p := decode[apiProfile](t, rec.Body.Bytes()); p.Goal != nil {
		t.Fatalf("coach de outro tenant não pode ver o perfil: %s", rec.Body.String())
	}

	// Coach: o aluno sem consentimento de saúde (revogado) é barrado.
	a.consents.revoke(a.studentID)
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/profile", a.coach, nil)
	if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "consent_required" {
		t.Fatalf("coach sem consentimento do aluno: %d %s", rec.Code, rec.Body.String())
	}
}
