package http_test

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
)

// newStudentPlan cria e publica um plano do aluno com os dias pedidos.
func (a templateActors) newStudentPlan(t *testing.T, token, studentID string, publish bool, labels ...string) string {
	t.Helper()
	rec := do(t, a.handler, http.MethodPost, "/v1/plans", token, map[string]any{"student_id": studentID, "title": "Plano"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar plano: %d %s", rec.Code, rec.Body.String())
	}
	id := decodePlanBody(t, rec.Body.Bytes()).ID
	a.saveTemplate(t, token, id, labels...)
	if publish {
		a.publishTemplate(t, token, id)
	}
	return id
}

type apiRotation struct {
	PlanID          string `json:"plan_id"`
	ActiveVersionID string `json:"active_version_id"`
	NextDayID       string `json:"next_day_id"`
	NextDayLabel    string `json:"next_day_label"`
}

type apiVersions struct {
	Items []struct {
		VersionNo      int    `json:"version_no"`
		PublishedAt    string `json:"published_at"`
		IsDraft        bool   `json:"is_draft"`
		PublishedBy    string `json:"published_by"`
		DaysCount      int    `json:"days_count"`
		ExercisesCount int    `json:"exercises_count"`
	} `json:"items"`
}

func (a templateActors) studentPlans(t *testing.T, token, studentID string) apiPlanList {
	t.Helper()
	rec := do(t, a.handler, http.MethodGet, "/v1/students/"+studentID+"/plans", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("listar planos: %d %s", rec.Code, rec.Body.String())
	}
	return decodeInto[apiPlanList](t, rec.Body.Bytes())
}

func (a templateActors) today(t *testing.T) apiToday {
	t.Helper()
	return decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
}

// TestPlanLifecycle é o Aceite do P6.2: duplicar nasce rascunho fora da
// rotação; ativar troca o treino do dia do aluno; o ativo não arquiva.
func TestPlanLifecycle(t *testing.T) {
	a := templateFixture(t)
	p1 := a.newStudentPlan(t, a.coachA, a.s1, true, "A", "B")
	if got := a.today(t); got.Plan == nil || got.Plan.ID != p1 {
		t.Fatalf("P1 deveria ser o treino do aluno: %+v", got.Plan)
	}

	// Duplicar: rascunho, mesmo aluno, árvore copiada, rotação intacta.
	rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.coachA, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("duplicar: %d %s", rec.Code, rec.Body.String())
	}
	p2 := decodePlanBody(t, rec.Body.Bytes()).ID
	dup := a.getPlan(t, a.coachA, p2, "")
	if p2 == p1 || dup.Status != "draft" || dup.StudentID != a.s1 || dup.Kind != "assigned" ||
		dup.SourceTemplateID != "" || dup.Version == nil || !dup.Version.IsDraft || len(dup.Version.Days) != 2 {
		t.Fatalf("cópia veio errada: %+v", dup)
	}
	if got := a.today(t); got.Plan.ID != p1 {
		t.Fatal("duplicar não pode mexer na rotação do aluno")
	}

	// Rascunho nunca publicado não entra na rotação.
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+p2+"/activate", a.coachA, nil)
	if rec.Code != http.StatusUnprocessableEntity || decodeError(t, rec).Code != "plan_not_published" {
		t.Fatalf("ativar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	// O ativo não arquiva.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/archive", a.coachA, nil)
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "plan_is_active" {
		t.Fatalf("arquivar o ativo: %d %s", rec.Code, rec.Body.String())
	}

	// Publica a cópia (vira a ativa, P1 é aposentado) e reativa P1.
	a.publishTemplate(t, a.coachA, p2)
	if got := a.today(t); got.Plan.ID != p2 {
		t.Fatalf("publicar P2 deveria trocar o treino: %+v", got.Plan)
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+p1+"/activate", a.coachA, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("ativar P1: %d %s", rec.Code, rec.Body.String())
	}
	rot := decodeInto[apiRotation](t, rec.Body.Bytes())
	if rot.PlanID != p1 || rot.NextDayLabel != "A" || rot.NextDayID == "" {
		t.Fatalf("rotação deveria recomeçar no A de P1: %+v", rot)
	}
	if got := a.today(t); got.Plan.ID != p1 || got.Day == nil || got.Day.Label != "A" {
		t.Fatalf("ativar deveria trocar o treino do dia: %+v", got)
	}
	// Idempotente: ativar o ativo não reinicia a rotação (aqui já no B).
	dayB := a.getPlan(t, a.coachA, p1, "").Version.Days[1].ID
	if rec = do(t, a.handler, http.MethodPut, "/v1/students/"+a.s1+"/plan/next-day", a.coachA, map[string]any{"day_id": dayB}); rec.Code != http.StatusOK {
		t.Fatalf("override: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+p1+"/activate", a.coachA, nil)
	if rec.Code != http.StatusOK || decodeInto[apiRotation](t, rec.Body.Bytes()).NextDayLabel != "B" {
		t.Fatalf("reativar o ativo não pode reiniciar a rotação: %d %s", rec.Code, rec.Body.String())
	}

	// Lista: P1 ativo/publicado, P2 arquivado.
	for _, item := range a.studentPlans(t, a.coachA, a.s1).Items {
		switch item.ID {
		case p1:
			if !item.IsActive || item.Status != "published" {
				t.Fatalf("P1: %+v", item)
			}
		case p2:
			if item.IsActive || item.Status != "archived" {
				t.Fatalf("P2: %+v", item)
			}
		}
	}

	// Arquivar o já arquivado é idempotente; aluno não arquiva nem ativa.
	for i := 0; i < 2; i++ {
		rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p2+"/archive", a.coachA, nil)
		if rec.Code != http.StatusOK || decodePlanBody(t, rec.Body.Bytes()).Status != "archived" {
			t.Fatalf("arquivar P2 (%d): %d %s", i, rec.Code, rec.Body.String())
		}
	}
	if rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p2+"/archive", a.student, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno arquivando: %d", rec.Code)
	}
	if rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+p2+"/activate", a.student, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno ativando: %d", rec.Code)
	}

	// Plano de outro aluno na URL do aluno: 404 (e modelo também).
	other := a.newStudentPlan(t, a.coachA, a.s2, true, "A")
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+other+"/activate", a.coachA, nil)
	if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "not_found" {
		t.Fatalf("ativar plano de outro aluno: %d %s", rec.Code, rec.Body.String())
	}
	tpl := a.newTemplate(t, a.coachA, "Modelo", true, "A")
	for _, path := range []string{"/v1/plans/" + tpl + "/archive", "/v1/plans/" + tpl + "/duplicate"} {
		if rec = do(t, a.handler, http.MethodPost, path, a.coachA, nil); rec.Code != http.StatusNotFound {
			t.Fatalf("%s em modelo: %d", path, rec.Code)
		}
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+tpl+"/activate", a.coachA, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("ativar modelo: %d", rec.Code)
	}

	// Arquivado não se edita nem se publica (publicar o reativaria por fora
	// do activate): 409 plan_archived, rotação intacta.
	rec = do(t, a.handler, http.MethodPut, "/v1/plans/"+p2+"/draft", a.coachA, draftBody(a.exerciseID, "X"))
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "plan_archived" {
		t.Fatalf("editar arquivado: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p2+"/publish", a.coachA, nil)
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "plan_archived" {
		t.Fatalf("publicar arquivado: %d %s", rec.Code, rec.Body.String())
	}
	if got := a.today(t); got.Plan.ID != p1 {
		t.Fatalf("tentar publicar arquivado não pode trocar o treino: %+v", got.Plan)
	}
	// Reativado pelo activate, volta a ser editável.
	if rec = do(t, a.handler, http.MethodPost, "/v1/students/"+a.s1+"/plans/"+p2+"/activate", a.coachA, nil); rec.Code != http.StatusOK {
		t.Fatalf("reativar P2: %d %s", rec.Code, rec.Body.String())
	}
	a.saveTemplate(t, a.coachA, p2, "X")
	a.publishTemplate(t, a.coachA, p2)
}

// Duplicar para outro aluno aplica vínculo, existência e a regra do coach_id.
func TestPlanDuplicateToOtherStudent(t *testing.T) {
	a := templateFixture(t)
	p1 := a.newStudentPlan(t, a.coachA, a.s1, true, "A", "B")
	body := func(student string) map[string]any { return map[string]any{"student_id": student} }

	rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.coachA, body(a.s2))
	if rec.Code != http.StatusCreated {
		t.Fatalf("duplicar para s2: %d %s", rec.Code, rec.Body.String())
	}
	got := decodePlanBody(t, rec.Body.Bytes())
	if got.StudentID != a.s2 || got.CoachID != a.coachAID || got.Status != "draft" {
		t.Fatalf("cópia para s2: %+v", got)
	}
	if _, err := a.studentPlansHas(t, a.s2, got.ID); err != nil {
		t.Fatal(err)
	}

	// s3 é do coachB: coachA não enxerga o aluno.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.coachA, body(a.s3))
	if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
		t.Fatalf("duplicar para aluno de outro coach: %d %s", rec.Code, rec.Body.String())
	}
	// coachB não lê o plano de s1.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.coachB, body(a.s3))
	if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
		t.Fatalf("coachB duplicando plano de s1: %d %s", rec.Code, rec.Body.String())
	}
	// Owner duplica para s3: o autor é o professor vinculado (coachB), não o owner.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.owner, body(a.s3))
	if rec.Code != http.StatusCreated {
		t.Fatalf("owner duplicando para s3: %d %s", rec.Code, rec.Body.String())
	}
	if got := decodePlanBody(t, rec.Body.Bytes()); got.CoachID == a.ownerID || got.StudentID != a.s3 {
		t.Fatalf("coach_id deveria ser o professor vinculado de s3: %+v", got)
	}
	// Aluno inexistente no identity: 404; id inválido: 400.
	a.identity.removeStudent(a.s2)
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.owner, body(a.s2))
	if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
		t.Fatalf("duplicar para aluno excluído: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.coachA, body("x"))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("student_id inválido: %d", rec.Code)
	}
	// Outro tenant não vê o plano.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+p1+"/duplicate", a.foreign, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("outro tenant duplicando: %d", rec.Code)
	}
}

func (a templateActors) studentPlansHas(t *testing.T, studentID, planID string) (bool, error) {
	t.Helper()
	for _, item := range a.studentPlans(t, a.owner, studentID).Items {
		if item.ID == planID {
			return true, nil
		}
	}
	t.Fatalf("plano %s não está na lista do aluno %s", planID, studentID)
	return false, nil
}

func TestPlanVersionsHistory(t *testing.T) {
	a := templateFixture(t)
	p := a.newStudentPlan(t, a.coachA, a.s1, true, "A", "B")
	a.saveTemplate(t, a.coachA, p, "A", "B", "C")
	a.publishTemplate(t, a.coachA, p)
	a.saveTemplate(t, a.coachA, p, "A") // rascunho v3

	rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+p+"/versions", a.coachA, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("versões: %d %s", rec.Code, rec.Body.String())
	}
	v := decodeInto[apiVersions](t, rec.Body.Bytes()).Items
	if len(v) != 3 || v[0].VersionNo != 3 || v[1].VersionNo != 2 || v[2].VersionNo != 1 {
		t.Fatalf("ordem das versões: %+v", v)
	}
	if !v[0].IsDraft || v[0].PublishedBy != "" || v[0].DaysCount != 1 {
		t.Fatalf("rascunho: %+v", v[0])
	}
	if v[1].IsDraft || v[1].PublishedBy != a.coachAID || v[1].DaysCount != 3 || v[1].ExercisesCount != 3 || v[1].PublishedAt == "" {
		t.Fatalf("v2: %+v", v[1])
	}
	if v[2].PublishedBy != a.coachAID || v[2].DaysCount != 2 || v[2].ExercisesCount != 2 {
		t.Fatalf("v1: %+v", v[2])
	}
	// Quem publica é o autor, mesmo sendo o owner.
	a.publishTemplate(t, a.owner, p)
	rec = do(t, a.handler, http.MethodGet, "/v1/plans/"+p+"/versions", a.owner, nil)
	if got := decodeInto[apiVersions](t, rec.Body.Bytes()).Items[0]; got.PublishedBy != a.ownerID {
		t.Fatalf("autor da v3: %+v", got)
	}
	// Acesso: outro coach 404, outro tenant 404, aluno 403, id inválido 400.
	for tok, want := range map[string]int{a.coachB: 404, a.foreign: 404, a.student: 403} {
		if rec = do(t, a.handler, http.MethodGet, "/v1/plans/"+p+"/versions", tok, nil); rec.Code != want {
			t.Fatalf("versões com outro ator: %d (esperava %d)", rec.Code, want)
		}
	}
	if rec = do(t, a.handler, http.MethodGet, "/v1/plans/xx/versions", a.coachA, nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("id inválido: %d", rec.Code)
	}
}

// O override do coach aparece no /me/today do aluno.
func TestCoachNextDayOverride(t *testing.T) {
	a := templateFixture(t)
	p := a.newStudentPlan(t, a.coachA, a.s1, true, "A", "B", "C")
	days := a.getPlan(t, a.coachA, p, "").Version.Days
	if got := a.today(t); got.Day.Label != "A" {
		t.Fatalf("começa no A: %+v", got.Day)
	}

	url := "/v1/students/" + a.s1 + "/plan/next-day"
	rec := do(t, a.handler, http.MethodPut, url, a.coachA, map[string]any{"day_id": days[2].ID})
	if rec.Code != http.StatusOK {
		t.Fatalf("override: %d %s", rec.Code, rec.Body.String())
	}
	if rot := decodeInto[apiRotation](t, rec.Body.Bytes()); rot.PlanID != p || rot.NextDayID != days[2].ID || rot.NextDayLabel != "C" {
		t.Fatalf("rotação: %+v", rot)
	}
	if got := a.today(t); got.Day == nil || got.Day.Label != "C" {
		t.Fatalf("o aluno deveria ver o C: %+v", got.Day)
	}

	// Dia de outro plano: 422; dia inválido: 400; aluno sem plano: 404.
	otherPlan := a.newStudentPlan(t, a.coachA, a.s2, true, "A")
	foreign := a.getPlan(t, a.coachA, otherPlan, "").Version.Days[0].ID
	rec = do(t, a.handler, http.MethodPut, url, a.coachA, map[string]any{"day_id": foreign})
	if rec.Code != http.StatusUnprocessableEntity || decodeError(t, rec).Code != "day_not_in_plan" {
		t.Fatalf("dia de outro plano: %d %s", rec.Code, rec.Body.String())
	}
	if rec = do(t, a.handler, http.MethodPut, url, a.coachA, map[string]any{"day_id": "x"}); rec.Code != http.StatusBadRequest {
		t.Fatalf("day_id inválido: %d", rec.Code)
	}
	a.identity.addStudent(a.s2)
	noPlan := uuid.NewString()
	a.identity.assign(a.coachAID, a.s1, a.s2, noPlan)
	rec = do(t, a.handler, http.MethodPut, "/v1/students/"+noPlan+"/plan/next-day", a.coachA, map[string]any{"day_id": days[0].ID})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("aluno sem plano: %d %s", rec.Code, rec.Body.String())
	}
	// Vínculo: coachB não mexe na rotação de s1; o aluno não usa esta rota.
	rec = do(t, a.handler, http.MethodPut, url, a.coachB, map[string]any{"day_id": days[0].ID})
	if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
		t.Fatalf("coachB: %d %s", rec.Code, rec.Body.String())
	}
	if rec = do(t, a.handler, http.MethodPut, url, a.student, map[string]any{"day_id": days[0].ID}); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno: %d", rec.Code)
	}
}
