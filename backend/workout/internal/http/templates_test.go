package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/coachlink"
)

// templateActors: dois coaches e um owner no mesmo tenant, com o vínculo
// coach↔aluno de verdade (coachlink contra um identity fake, ADR-016):
// coachA tem s1 e s2; coachB tem s3.
type templateActors struct {
	handler    http.Handler
	tenant     string
	coachA     string
	coachAID   string
	ownerID    string
	identity   *fakeIdentity
	coachB     string
	owner      string
	student    string // token do aluno s1
	foreign    string // coach de outro tenant
	s1, s2, s3 string
	exerciseID string
}

func templateFixture(t *testing.T) templateActors {
	t.Helper()
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	identity := newFakeIdentity(t)
	handler := newTestRouterWithLinker(t, publicPEM, pool, coachlink.NewClient(identity.server.URL, testInternalToken, 0))

	tenant := uuid.NewString()
	coachAID, coachBID := uuid.NewString(), uuid.NewString()
	s1, s2, s3 := uuid.NewString(), uuid.NewString(), uuid.NewString()
	identity.assign(coachAID, s1, s2)
	identity.assign(coachBID, s3)
	exp := time.Now().Add(time.Minute)
	ownerID := uuid.NewString()
	a := templateActors{
		handler: handler, tenant: tenant, coachAID: coachAID, ownerID: ownerID, identity: identity,
		coachA:  signTokenAs(t, priv, tenant, coachAID, []string{"coach"}, exp),
		coachB:  signTokenAs(t, priv, tenant, coachBID, []string{"coach"}, exp),
		owner:   signTokenAs(t, priv, tenant, ownerID, []string{"owner", "coach"}, exp),
		student: signTokenAs(t, priv, tenant, s1, []string{"student"}, exp),
		foreign: signTokenAs(t, priv, uuid.NewString(), uuid.NewString(), []string{"coach"}, exp),
		s1:      s1, s2: s2, s3: s3,
	}
	a.exerciseID = requireSeededLibrary(t, handler, a.coachA).ID
	return a
}

type apiTemplateList struct {
	Items []struct {
		ID                 string `json:"id"`
		Title              string `json:"title"`
		Status             string `json:"status"`
		PublishedVersionNo int    `json:"published_version_no"`
		DaysCount          int    `json:"days_count"`
		ExercisesCount     int    `json:"exercises_count"`
		AssignedCount      int    `json:"assigned_count"`
	} `json:"items"`
	NextCursor string `json:"next_cursor"`
}

type apiBatch struct {
	Items []struct {
		StudentID string `json:"student_id"`
		PlanID    string `json:"plan_id"`
		VersionNo int    `json:"version_no"`
		OK        bool   `json:"ok"`
		Error     *struct {
			Code string `json:"code"`
		} `json:"error"`
	} `json:"items"`
}

type apiRecipients struct {
	TemplateVersionNo int `json:"template_version_no"`
	Items             []struct {
		PlanID            string `json:"plan_id"`
		StudentID         string `json:"student_id"`
		Status            string `json:"status"`
		IsActive          bool   `json:"is_active"`
		SourceVersionNo   int    `json:"source_version_no"`
		EditedAfterSource bool   `json:"edited_after_source"`
	} `json:"items"`
}

func decodeInto[T any](t *testing.T, raw []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("decodificar: %v (%s)", err, raw)
	}
	return v
}

// newTemplate cria o modelo com os dias pedidos; publica quando pedido.
func (a templateActors) newTemplate(t *testing.T, token, title string, publish bool, labels ...string) string {
	t.Helper()
	rec := do(t, a.handler, http.MethodPost, "/v1/templates", token, map[string]any{"title": title, "description": "Modelo de teste"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar modelo: %d %s", rec.Code, rec.Body.String())
	}
	plan := decodePlanBody(t, rec.Body.Bytes())
	if plan.Kind != "template" || plan.StudentID != "" || plan.Status != "draft" {
		t.Fatalf("modelo recém-criado veio errado: %+v", plan)
	}
	if len(labels) > 0 {
		a.saveTemplate(t, token, plan.ID, labels...)
	}
	if publish {
		a.publishTemplate(t, token, plan.ID)
	}
	return plan.ID
}

func (a templateActors) saveTemplate(t *testing.T, token, id string, labels ...string) {
	t.Helper()
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+id+"/draft", token, draftBody(a.exerciseID, labels...)); rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho do modelo: %d %s", rec.Code, rec.Body.String())
	}
}

func (a templateActors) publishTemplate(t *testing.T, token, id string) {
	t.Helper()
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+id+"/publish", token, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar modelo: %d %s", rec.Code, rec.Body.String())
	}
}

func (a templateActors) getPlan(t *testing.T, token, id, query string) apiPlan {
	t.Helper()
	rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+id+query, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("ler plano %s: %d %s", id, rec.Code, rec.Body.String())
	}
	return decodePlanBody(t, rec.Body.Bytes())
}

// TestTemplateAssignCopiesAreIndependent é o Aceite do P6.1: aplicar o modelo a
// 3 alunos cria 3 planos independentes — editar o modelo depois não muda
// nenhum deles — e um aluno fora do vínculo falha só no item dele.
func TestTemplateAssignCopiesAreIndependent(t *testing.T) {
	a := templateFixture(t)
	tplID := a.newTemplate(t, a.coachA, "Full body", true, "A", "B")

	// coachA tem s1 e s2; s3 é do coachB. O lote não cai por causa dele.
	rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA, map[string]any{
		"student_ids": []string{a.s1, a.s2, a.s3}, "publish": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("atribuir: %d %s", rec.Code, rec.Body.String())
	}
	batch := decodeInto[apiBatch](t, rec.Body.Bytes())
	if len(batch.Items) != 3 || !batch.Items[0].OK || !batch.Items[1].OK {
		t.Fatalf("s1 e s2 deveriam ter recebido: %+v", batch.Items)
	}
	if batch.Items[2].OK || batch.Items[2].Error == nil || batch.Items[2].Error.Code != "student_not_found" {
		t.Fatalf("s3 (de outro coach) deveria dar student_not_found: %+v", batch.Items[2])
	}
	p1, p2 := batch.Items[0].PlanID, batch.Items[1].PlanID
	if p1 == p2 || p1 == tplID {
		t.Fatalf("cada aluno deveria ter plano próprio: %s %s", p1, p2)
	}

	// publish=true: o plano já está na rotação do aluno.
	rec = do(t, a.handler, http.MethodGet, "/v1/me/plan", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("aluno lendo plano: %d %s", rec.Code, rec.Body.String())
	}
	mine := decodePlanBody(t, rec.Body.Bytes())
	if mine.ID != p1 || mine.Kind != "assigned" || mine.Title != "Full body" || len(mine.Version.Days) != 2 ||
		mine.NextDayID != mine.Version.Days[0].ID {
		t.Fatalf("plano do aluno veio errado: %+v", mine)
	}
	copy1 := a.getPlan(t, a.coachA, p1, "")
	if copy1.SourceTemplateID != tplID || copy1.SourceVersionNo != 1 {
		t.Fatalf("procedência não gravada: %+v", copy1)
	}
	// Árvore própria: ids de dia diferentes do modelo e entre os alunos.
	tpl := a.getPlan(t, a.coachA, tplID, "")
	if tpl.Version.Days[0].ID == copy1.Version.Days[0].ID ||
		copy1.Version.Days[0].ID == a.getPlan(t, a.coachA, p2, "").Version.Days[0].ID {
		t.Fatal("a cópia deveria ter dias com ids próprios")
	}
	firstSet := copy1.Version.Days[0].Blocks[0].Exercises[0].Sets[0]
	if copy1.Version.Days[0].Blocks[0].BlockType != "superset" || *firstSet.RepsMin != 8 || *firstSet.TargetLoadKg != 40 {
		t.Fatalf("a cópia deveria ser profunda e fiel: %+v", copy1.Version.Days[0].Blocks[0])
	}

	// Editar o modelo (v2 com 3 dias) não mexe em nenhum plano de aluno.
	a.saveTemplate(t, a.coachA, tplID, "A", "B", "C")
	a.publishTemplate(t, a.coachA, tplID)
	if got := a.getPlan(t, a.coachA, p1, ""); len(got.Version.Days) != 2 || got.Version.VersionNo != 1 {
		t.Fatalf("editar o modelo não pode mudar o plano do aluno: %+v", got.Version)
	}
	// E editar o plano do aluno não mexe no modelo.
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+p2+"/draft", a.coachA, draftBody(a.exerciseID, "X")); rec.Code != http.StatusOK {
		t.Fatalf("editar plano do aluno: %d %s", rec.Code, rec.Body.String())
	}
	if got := a.getPlan(t, a.coachA, tplID, "?version=2"); len(got.Version.Days) != 3 {
		t.Fatalf("editar o plano do aluno não pode mudar o modelo: %+v", got.Version)
	}

	// A lista do aluno traz o plano com a procedência; o modelo não aparece.
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.s1+"/plans", a.coachA, nil)
	list := decodeInto[struct {
		Items []struct {
			ID               string `json:"id"`
			Kind             string `json:"kind"`
			SourceTemplateID string `json:"source_template_id"`
		} `json:"items"`
	}](t, rec.Body.Bytes())
	if len(list.Items) != 1 || list.Items[0].ID != p1 || list.Items[0].Kind != "assigned" || list.Items[0].SourceTemplateID != tplID {
		t.Fatalf("lista do aluno deveria ter só o plano atribuído: %+v", list.Items)
	}
}

func TestTemplateAssignErrors(t *testing.T) {
	a := templateFixture(t)

	t.Run("modelo sem versão publicada", func(t *testing.T) {
		draftOnly := a.newTemplate(t, a.coachA, "Rascunho", false, "A")
		rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+draftOnly+"/assign", a.coachA,
			map[string]any{"student_ids": []string{a.s1}})
		if rec.Code != http.StatusUnprocessableEntity || decodeError(t, rec).Code != "template_not_published" {
			t.Fatalf("esperava 422 template_not_published, veio %d %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("sem publicar o plano nasce rascunho e fora da rotação", func(t *testing.T) {
		tplID := a.newTemplate(t, a.coachA, "Rascunho no aluno", true, "A")
		rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA,
			map[string]any{"student_ids": []string{a.s2}, "publish": false})
		batch := decodeInto[apiBatch](t, rec.Body.Bytes())
		if rec.Code != http.StatusOK || len(batch.Items) != 1 || !batch.Items[0].OK {
			t.Fatalf("atribuir sem publicar: %d %s", rec.Code, rec.Body.String())
		}
		plan := a.getPlan(t, a.coachA, batch.Items[0].PlanID, "")
		if plan.Status != "draft" || plan.Version == nil || !plan.Version.IsDraft || plan.ActiveVersionID != "" {
			t.Fatalf("deveria ser rascunho fora da rotação: %+v", plan)
		}
	})

	t.Run("lote inválido", func(t *testing.T) {
		tplID := a.newTemplate(t, a.coachA, "Lote", true, "A")
		for _, ids := range [][]string{nil, {"nao-uuid"}} {
			rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA, map[string]any{"student_ids": ids})
			if rec.Code != http.StatusBadRequest || decodeError(t, rec).Code != "validation_error" {
				t.Fatalf("esperava 400 validation_error, veio %d %s", rec.Code, rec.Body.String())
			}
		}
	})

	t.Run("plano de aluno não é modelo", func(t *testing.T) {
		rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.coachA, map[string]any{"student_id": a.s1, "title": "Normal"})
		planID := decodePlanBody(t, rec.Body.Bytes()).ID
		rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+planID+"/assign", a.coachA, map[string]any{"student_ids": []string{a.s1}})
		if rec.Code != http.StatusNotFound {
			t.Fatalf("esperava 404, veio %d %s", rec.Code, rec.Body.String())
		}
	})
}

// TestTemplateReapply: reaplicar gera versão nova só nos planos escolhidos e
// descarta os ajustes individuais (ADR-018).
func TestTemplateReapply(t *testing.T) {
	a := templateFixture(t)
	tplID := a.newTemplate(t, a.coachA, "Reaplicar", true, "A", "B")
	rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA, map[string]any{
		"student_ids": []string{a.s1, a.s2}, "publish": true,
	})
	batch := decodeInto[apiBatch](t, rec.Body.Bytes())
	p1, p2 := batch.Items[0].PlanID, batch.Items[1].PlanID

	// O coach ajusta o plano do s2; o s1 fica como veio.
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+p2+"/draft", a.coachA, draftBody(a.exerciseID, "X")); rec.Code != http.StatusOK {
		t.Fatalf("ajustar plano: %d %s", rec.Code, rec.Body.String())
	}

	// O modelo evolui para a v2 com 3 dias.
	a.saveTemplate(t, a.coachA, tplID, "A", "B", "C")
	a.publishTemplate(t, a.coachA, tplID)

	rec = do(t, a.handler, http.MethodGet, "/v1/templates/"+tplID+"/recipients", a.coachA, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("destinatários: %d %s", rec.Code, rec.Body.String())
	}
	rcpt := decodeInto[apiRecipients](t, rec.Body.Bytes())
	if rcpt.TemplateVersionNo != 2 || len(rcpt.Items) != 2 {
		t.Fatalf("esperava 2 destinatários e modelo na v2: %+v", rcpt)
	}
	byPlan := map[string]int{}
	for i, it := range rcpt.Items {
		byPlan[it.PlanID] = i
		if it.SourceVersionNo != 1 || !it.IsActive {
			t.Fatalf("destinatário deveria estar na v1 e ativo: %+v", it)
		}
	}
	if rcpt.Items[byPlan[p1]].EditedAfterSource || !rcpt.Items[byPlan[p2]].EditedAfterSource {
		t.Fatalf("só o plano do s2 foi editado: %+v", rcpt.Items)
	}

	// Reaplica só no s2 (e num plano que não é deste modelo, que falha sozinho).
	other := decodePlanBody(t, do(t, a.handler, http.MethodPost, "/v1/plans", a.coachA,
		map[string]any{"student_id": a.s1, "title": "Outro"}).Body.Bytes()).ID
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/reapply", a.coachA,
		map[string]any{"plan_ids": []string{p2, other}})
	if rec.Code != http.StatusOK {
		t.Fatalf("reaplicar: %d %s", rec.Code, rec.Body.String())
	}
	res := decodeInto[apiBatch](t, rec.Body.Bytes())
	if !res.Items[0].OK || res.Items[0].VersionNo != 2 {
		// v1 publicada, v2 = rascunho do ajuste (substituído) e publicado na reaplicação.
		t.Fatalf("reaplicação deveria publicar versão nova: %+v", res.Items[0])
	}
	if res.Items[1].OK || res.Items[1].Error == nil || res.Items[1].Error.Code != "plan_not_from_template" {
		t.Fatalf("plano alheio ao modelo deveria falhar no item: %+v", res.Items[1])
	}

	got := a.getPlan(t, a.coachA, p2, "")
	if got.Version.VersionNo != res.Items[0].VersionNo || got.Version.IsDraft || len(got.Version.Days) != 3 {
		t.Fatalf("plano do s2 deveria ter a árvore do modelo v2 publicada: %+v", got.Version)
	}
	if untouched := a.getPlan(t, a.coachA, p1, ""); len(untouched.Version.Days) != 2 || untouched.Version.VersionNo != 1 {
		t.Fatalf("plano não escolhido não pode mudar: %+v", untouched.Version)
	}
	// O histórico do s2 continua: a v1 ainda tem os 2 dias originais.
	if v1 := a.getPlan(t, a.coachA, p2, "?version=1"); len(v1.Version.Days) != 2 {
		t.Fatalf("v1 deveria continuar intacta: %+v", v1.Version)
	}
	rcpt = decodeInto[apiRecipients](t, do(t, a.handler, http.MethodGet, "/v1/templates/"+tplID+"/recipients", a.coachA, nil).Body.Bytes())
	for _, it := range rcpt.Items {
		if it.PlanID == p2 && (it.SourceVersionNo != 2 || it.EditedAfterSource) {
			t.Fatalf("s2 deveria estar na v2 e sem edição: %+v", it)
		}
	}

	// O coachB não enxerga destinatários que não são dele.
	rcptB := decodeInto[apiRecipients](t, do(t, a.handler, http.MethodGet, "/v1/templates/"+tplID+"/recipients", a.coachB, nil).Body.Bytes())
	if len(rcptB.Items) != 0 {
		t.Fatalf("coachB não deveria ver alunos de A: %+v", rcptB.Items)
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/reapply", a.coachB, map[string]any{"plan_ids": []string{p1}})
	if r := decodeInto[apiBatch](t, rec.Body.Bytes()); r.Items[0].OK || r.Items[0].Error.Code != "student_not_found" {
		t.Fatalf("coachB não pode reaplicar no plano de A: %s", rec.Body.String())
	}
}

func TestTemplatePermissions(t *testing.T) {
	a := templateFixture(t)
	tplID := a.newTemplate(t, a.coachA, "Do A", true, "A")

	// Qualquer coach do tenant lê e lista; só o autor ou o owner altera.
	if rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+tplID, a.coachB, nil); rec.Code != http.StatusOK {
		t.Fatalf("outro coach deveria ler o modelo: %d", rec.Code)
	}
	rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+tplID+"/draft", a.coachB, draftBody(a.exerciseID, "A"))
	if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "template_not_owned" {
		t.Fatalf("outro coach não edita o modelo: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+tplID+"/publish", a.coachB, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("outro coach não publica o modelo: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/archive", a.coachB, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("outro coach não arquiva o modelo: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+tplID+"/draft", a.owner, draftBody(a.exerciseID, "A", "B")); rec.Code != http.StatusOK {
		t.Fatalf("owner edita qualquer modelo: %d %s", rec.Code, rec.Body.String())
	}
	// Mas o outro coach aplica (ADR-018 §3): s3 é dele.
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachB, map[string]any{"student_ids": []string{a.s3}})
	if r := decodeInto[apiBatch](t, rec.Body.Bytes()); rec.Code != http.StatusOK || !r.Items[0].OK {
		t.Fatalf("outro coach aplica o modelo ao próprio aluno: %d %s", rec.Code, rec.Body.String())
	}

	// Aluno e outro tenant não chegam ao modelo.
	if rec := do(t, a.handler, http.MethodGet, "/v1/templates", a.student, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não lista modelos: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+tplID, a.foreign, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("outro tenant deveria receber 404: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.foreign, map[string]any{"student_ids": []string{a.s1}}); rec.Code != http.StatusNotFound {
		t.Fatalf("assign de outro tenant deveria receber 404: %d", rec.Code)
	}
	list := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates", a.foreign, nil).Body.Bytes())
	if len(list.Items) != 0 {
		t.Fatalf("outro tenant não lista modelos: %+v", list.Items)
	}

	// Arquivar (autor): sai da lista padrão, volta em status=archived e não
	// aceita edição nem atribuição; planos já atribuídos seguem.
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/archive", a.coachA, nil)
	if rec.Code != http.StatusOK || decodePlanBody(t, rec.Body.Bytes()).Status != "archived" {
		t.Fatalf("arquivar: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/archive", a.coachA, nil); rec.Code != http.StatusOK {
		t.Fatalf("arquivar é idempotente: %d", rec.Code)
	}
	for _, status := range []string{"", "archived"} {
		l := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates?status="+status, a.coachA, nil).Body.Bytes())
		if (status == "") == (len(l.Items) > 0) {
			t.Fatalf("filtro status=%q errado: %+v", status, l.Items)
		}
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA, map[string]any{"student_ids": []string{a.s1}})
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "template_archived" {
		t.Fatalf("modelo arquivado não é atribuído: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+tplID+"/draft", a.coachA, draftBody(a.exerciseID, "A")); rec.Code != http.StatusConflict {
		t.Fatalf("modelo arquivado não é editado: %d", rec.Code)
	}
}

// TestTemplateNeverLeaksToStudentSurfaces: publicar modelo não toca rotação,
// /me/plan, /me/today nem o resumo de alunos (ADR-018 §4).
func TestTemplateNeverLeaksToStudentSurfaces(t *testing.T) {
	a := templateFixture(t)
	a.newTemplate(t, a.coachA, "Só modelo", true, "A", "B")

	if rec := do(t, a.handler, http.MethodGet, "/v1/me/plan", a.student, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("/me/plan não pode ver modelo: %d %s", rec.Code, rec.Body.String())
	}
	rec := do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil)
	if today := decodeInto[struct {
		Status string `json:"status"`
	}](t, rec.Body.Bytes()); rec.Code != http.StatusOK || today.Status != "no_plan" {
		t.Fatalf("/me/today não pode ver modelo: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/students/overview", a.owner, map[string]any{"student_ids": []string{a.s1}})
	var ov struct {
		Items []struct {
			ActivePlan *struct{} `json:"active_plan"`
		} `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &ov); err != nil {
		t.Fatalf("overview: %v", err)
	}
	for _, it := range ov.Items {
		if it.ActivePlan != nil {
			t.Fatalf("modelo não é plano ativo de ninguém: %s", rec.Body.String())
		}
	}
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.s1+"/plans", a.coachA, nil)
	if got := decodeInto[apiPlanList](t, rec.Body.Bytes()); len(got.Items) != 0 {
		t.Fatalf("lista de planos do aluno não pode trazer modelo: %+v", got.Items)
	}
}

func TestTemplateListSearchAndPaging(t *testing.T) {
	a := templateFixture(t)
	a.newTemplate(t, a.coachA, "Hipertrofia ABC", true, "A", "B", "C")
	a.newTemplate(t, a.coachA, "Força 5x5", true, "A")
	a.newTemplate(t, a.coachB, "Hipertrofia Iniciante", false)

	// Busca sem acento e sem caixa; contagens da versão publicada.
	l := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates?q=forca", a.coachA, nil).Body.Bytes())
	if len(l.Items) != 1 || l.Items[0].Title != "Força 5x5" || l.Items[0].DaysCount != 1 ||
		l.Items[0].ExercisesCount != 1 || l.Items[0].PublishedVersionNo != 1 {
		t.Fatalf("busca por 'forca': %+v", l.Items)
	}
	l = decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates?q=hipertrofia", a.coachB, nil).Body.Bytes())
	if len(l.Items) != 2 {
		t.Fatalf("modelos de outros coaches também listam: %+v", l.Items)
	}

	// Paginação por cursor: página de 2 e depois a última; sem repetir nem pular.
	p1 := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates?limit=2", a.coachA, nil).Body.Bytes())
	if len(p1.Items) != 2 || p1.NextCursor == "" {
		t.Fatalf("primeira página: %+v", p1)
	}
	p2 := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates?limit=2&cursor="+p1.NextCursor, a.coachA, nil).Body.Bytes())
	if len(p2.Items) != 1 || p2.NextCursor != "" {
		t.Fatalf("segunda página: %+v", p2)
	}
	seen := map[string]bool{}
	for _, it := range append(p1.Items, p2.Items...) {
		if seen[it.ID] {
			t.Fatalf("modelo repetido entre páginas: %s", it.ID)
		}
		seen[it.ID] = true
	}
	if rec := do(t, a.handler, http.MethodGet, "/v1/templates?cursor=lixo", a.coachA, nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("cursor inválido deveria dar 400: %d", rec.Code)
	}
}

func TestSaveAsTemplate(t *testing.T) {
	a := templateFixture(t)
	rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.coachA, map[string]any{"student_id": a.s1, "title": "Plano do João"})
	planID := decodePlanBody(t, rec.Body.Bytes()).ID

	// Sem nada salvo ainda: não há o que copiar.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/save-as-template", a.coachA, nil)
	if rec.Code != http.StatusUnprocessableEntity || decodeError(t, rec).Code != "plan_incomplete" {
		t.Fatalf("plano vazio: %d %s", rec.Code, rec.Body.String())
	}

	// Publicado v1 (2 dias) + rascunho v2 (3 dias): copia o rascunho, o que o builder mostra.
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coachA, draftBody(a.exerciseID, "A", "B")); rec.Code != http.StatusOK {
		t.Fatalf("salvar: %d", rec.Code)
	}
	a.publishTemplate(t, a.coachA, planID)
	a.saveTemplate(t, a.coachA, planID, "A", "B", "C")

	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/save-as-template", a.coachA, map[string]any{"title": "Modelo ABC"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("salvar como modelo: %d %s", rec.Code, rec.Body.String())
	}
	tpl := decodePlanBody(t, rec.Body.Bytes())
	if tpl.Kind != "template" || tpl.Title != "Modelo ABC" || tpl.StudentID != "" || tpl.Status != "draft" ||
		tpl.Version == nil || len(tpl.Version.Days) != 3 || tpl.CoachID != a.coachAID {
		t.Fatalf("modelo veio errado: %+v", tpl)
	}
	// Sem procedência: o modelo não é filho do plano.
	if got := a.getPlan(t, a.coachA, tpl.ID, ""); got.StudentID != "" {
		t.Fatalf("modelo não tem aluno: %+v", got)
	}

	// Plano de aluno fora do vínculo: 404; modelo como origem: 404.
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/save-as-template", a.coachB, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("coachB não salva plano do aluno de A: %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+tpl.ID+"/save-as-template", a.coachA, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("modelo não é origem: %d", rec.Code)
	}
}

func (a templateActors) coachOf(t *testing.T, planID string) string {
	t.Helper()
	return a.getPlan(t, a.owner, planID, "").CoachID
}

// TestTemplateUnarchive: desarquivar tem a mesma permissão do arquivar,
// devolve o modelo à lista padrão no status certo e é idempotente.
func TestTemplateUnarchive(t *testing.T) {
	a := templateFixture(t)
	published := a.newTemplate(t, a.coachA, "Publicado", true, "A")
	draftOnly := a.newTemplate(t, a.coachA, "Só rascunho", false, "A")
	for _, id := range []string{published, draftOnly} {
		if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+id+"/archive", a.coachA, nil); rec.Code != http.StatusOK {
			t.Fatalf("arquivar: %d", rec.Code)
		}
	}

	rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+published+"/unarchive", a.coachB, nil)
	if rec.Code != http.StatusForbidden || decodeError(t, rec).Code != "template_not_owned" {
		t.Fatalf("outro coach não desarquiva: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+published+"/unarchive", a.foreign, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("outro tenant: %d", rec.Code)
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+published+"/unarchive", a.coachA, nil)
	if rec.Code != http.StatusOK || decodePlanBody(t, rec.Body.Bytes()).Status != "published" {
		t.Fatalf("autor desarquiva (volta published): %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+published+"/unarchive", a.coachA, nil); rec.Code != http.StatusOK {
		t.Fatalf("desarquivar é idempotente: %d", rec.Code)
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+draftOnly+"/unarchive", a.owner, nil)
	if rec.Code != http.StatusOK || decodePlanBody(t, rec.Body.Bytes()).Status != "draft" {
		t.Fatalf("owner desarquiva (sem publicada volta draft): %d %s", rec.Code, rec.Body.String())
	}

	// De volta na lista padrão e atribuível de novo.
	l := decodeInto[apiTemplateList](t, do(t, a.handler, http.MethodGet, "/v1/templates", a.coachA, nil).Body.Bytes())
	if len(l.Items) != 2 {
		t.Fatalf("os dois deveriam voltar à lista: %+v", l.Items)
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+published+"/assign", a.coachA, map[string]any{"student_ids": []string{a.s1}})
	if r := decodeInto[apiBatch](t, rec.Body.Bytes()); rec.Code != http.StatusOK || !r.Items[0].OK {
		t.Fatalf("modelo desarquivado volta a ser atribuível: %d %s", rec.Code, rec.Body.String())
	}
	// Plano de aluno não é modelo.
	plan := decodePlanBody(t, do(t, a.handler, http.MethodPost, "/v1/plans", a.coachA, map[string]any{"student_id": a.s1, "title": "N"}).Body.Bytes())
	if rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+plan.ID+"/unarchive", a.coachA, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("plano de aluno em /unarchive: %d", rec.Code)
	}
}

// TestAssignCoachIsLinkedCoach: o plano criado fica com o professor vinculado
// ao aluno (ADR-016), não com quem atribuiu; sem vínculo, com quem atribuiu.
func TestAssignCoachIsLinkedCoach(t *testing.T) {
	a := templateFixture(t)
	tplID := a.newTemplate(t, a.coachA, "Coach", true, "A")
	orphan := uuid.NewString()
	a.identity.addStudent(orphan)

	// Owner atribui a s1 (de A), s3 (de B) e a um aluno sem professor.
	rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.owner, map[string]any{
		"student_ids": []string{a.s1, a.s3, orphan},
	})
	batch := decodeInto[apiBatch](t, rec.Body.Bytes())
	if rec.Code != http.StatusOK || len(batch.Items) != 3 {
		t.Fatalf("owner atribui: %d %s", rec.Code, rec.Body.String())
	}
	for _, it := range batch.Items {
		if !it.OK {
			t.Fatalf("item deveria passar: %+v", it)
		}
	}
	if got := a.coachOf(t, batch.Items[0].PlanID); got != a.coachAID {
		t.Fatalf("plano do s1 deveria ficar com o coach A (%s), veio %s", a.coachAID, got)
	}
	coachBID := a.coachOf(t, batch.Items[1].PlanID)
	if coachBID == a.ownerID || coachBID == a.coachAID {
		t.Fatalf("plano do s3 deveria ficar com o coach B, veio %s", coachBID)
	}
	if got := a.coachOf(t, batch.Items[2].PlanID); got != a.ownerID {
		t.Fatalf("aluno sem professor: fica com quem atribuiu (%s), veio %s", a.ownerID, got)
	}

	// POST /v1/plans segue a mesma regra.
	rec = do(t, a.handler, http.MethodPost, "/v1/plans", a.owner, map[string]any{"student_id": a.s3, "title": "Do owner"})
	if rec.Code != http.StatusCreated || decodePlanBody(t, rec.Body.Bytes()).CoachID != coachBID {
		t.Fatalf("POST /plans do owner deveria usar o coach vinculado: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/plans", a.owner, map[string]any{"student_id": orphan, "title": "Sem coach"})
	if rec.Code != http.StatusCreated || decodePlanBody(t, rec.Body.Bytes()).CoachID != a.ownerID {
		t.Fatalf("POST /plans sem vínculo fica com o owner: %d %s", rec.Code, rec.Body.String())
	}
	// Coach A atribuindo ao próprio aluno: ele mesmo.
	rec = do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.coachA, map[string]any{"student_ids": []string{a.s2}})
	if got := a.coachOf(t, decodeInto[apiBatch](t, rec.Body.Bytes()).Items[0].PlanID); got != a.coachAID {
		t.Fatalf("coach A atribuindo ao próprio aluno: %s", got)
	}
}

// TestPlanCreationValidatesStudentExists: aluno inexistente/excluído não
// recebe plano (assign por item, POST /plans inteiro); inativo recebe.
func TestPlanCreationValidatesStudentExists(t *testing.T) {
	a := templateFixture(t)
	tplID := a.newTemplate(t, a.coachA, "Existe", true, "A")
	gone, inactive := uuid.NewString(), uuid.NewString()
	a.identity.assign(a.coachAID, a.s1, a.s2, gone, inactive)
	a.identity.removeStudent(gone) // excluído: o vínculo ainda cita, o status não volta
	a.identity.setStatus(inactive, "inactive")
	unknown := uuid.NewString() // owner vê qualquer id; o identity não o conhece

	rec := do(t, a.handler, http.MethodPost, "/v1/templates/"+tplID+"/assign", a.owner, map[string]any{
		"student_ids": []string{a.s1, gone, unknown, inactive},
	})
	batch := decodeInto[apiBatch](t, rec.Body.Bytes())
	if rec.Code != http.StatusOK || len(batch.Items) != 4 {
		t.Fatalf("assign: %d %s", rec.Code, rec.Body.String())
	}
	if !batch.Items[0].OK || !batch.Items[3].OK {
		t.Fatalf("aluno ativo e inativo recebem plano: %+v", batch.Items)
	}
	for _, i := range []int{1, 2} {
		if batch.Items[i].OK || batch.Items[i].Error == nil || batch.Items[i].Error.Code != "student_not_found" {
			t.Fatalf("item %d deveria ser student_not_found: %+v", i, batch.Items[i])
		}
	}

	for name, token := range map[string]string{"owner": a.owner, "coach": a.coachA} {
		for _, id := range []string{gone, unknown} {
			rec := do(t, a.handler, http.MethodPost, "/v1/plans", token, map[string]any{"student_id": id, "title": "X"})
			if rec.Code != http.StatusNotFound || decodeError(t, rec).Code != "student_not_found" {
				t.Fatalf("%s: POST /plans para %s: esperava 404 student_not_found, veio %d %s", name, id, rec.Code, rec.Body.String())
			}
		}
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.coachA, map[string]any{"student_id": inactive, "title": "Volta"}); rec.Code != http.StatusCreated {
		t.Fatalf("aluno inativo recebe plano: %d %s", rec.Code, rec.Body.String())
	}

	// Identity fora do ar: falha fechada (500), sem criar plano.
	a.identity.setDown(true)
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.owner, map[string]any{"student_id": a.s1, "title": "Y"}); rec.Code != http.StatusInternalServerError {
		t.Fatalf("identity fora: esperava 500, veio %d", rec.Code)
	}
}
