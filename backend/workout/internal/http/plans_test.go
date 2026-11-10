package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
)

// apiPlan espelha o payload do builder (P1.4) do lado do cliente.
type apiPlan struct {
	ID        string `json:"id"`
	StudentID string `json:"student_id"`
	CoachID   string `json:"coach_id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	Kind      string `json:"kind"`
	// Procedência quando o plano nasceu de um modelo (ADR-018).
	SourceTemplateID string `json:"source_template_id"`
	SourceVersionNo  int    `json:"source_version_no"`
	Version          *struct {
		ID          string  `json:"id"`
		VersionNo   int     `json:"version_no"`
		PublishedAt *string `json:"published_at"`
		IsDraft     bool    `json:"is_draft"`
		Days        []struct {
			ID       string `json:"id"`
			Label    string `json:"label"`
			Position int    `json:"position"`
			Title    string `json:"title"`
			Blocks   []struct {
				ID          string `json:"id"`
				BlockType   string `json:"block_type"`
				RestSeconds int    `json:"rest_seconds"`
				Exercises   []struct {
					ExerciseID string `json:"exercise_id"`
					Notes      string `json:"notes"`
					Exercise   *struct {
						ID       string `json:"id"`
						Name     string `json:"name"`
						Locale   string `json:"locale"`
						IsGlobal bool   `json:"is_global"`
					} `json:"exercise"`
					Sets []struct {
						SetNo        int      `json:"set_no"`
						RepsMin      *int     `json:"reps_min"`
						RepsMax      *int     `json:"reps_max"`
						TargetLoadKg *float64 `json:"target_load_kg"`
						TargetUnit   string   `json:"target_unit"`
						TargetValue  *float64 `json:"target_value"`
						RestSeconds  *int     `json:"rest_seconds"`
					} `json:"sets"`
				} `json:"exercises"`
			} `json:"blocks"`
		} `json:"days"`
	} `json:"version"`
	Versions []struct {
		VersionNo   int     `json:"version_no"`
		PublishedAt *string `json:"published_at"`
		IsDraft     bool    `json:"is_draft"`
	} `json:"versions"`
	ActiveVersionID string `json:"active_version_id"`
	NextDayID       string `json:"next_day_id"`
}

type apiPlanList struct {
	Items []struct {
		ID                 string `json:"id"`
		Title              string `json:"title"`
		Status             string `json:"status"`
		LatestVersionNo    int    `json:"latest_version_no"`
		PublishedVersionNo int    `json:"published_version_no"`
		HasDraft           bool   `json:"has_draft"`
		IsActive           bool   `json:"is_active"`
	} `json:"items"`
}

// builderFixture monta o router com banco real e devolve os atores do P1.4:
// o coach dono do plano, o aluno, outro coach do mesmo tenant e um coach de
// outro tenant.
type builderActors struct {
	handler    http.Handler
	tenantA    string
	coach      string // token do coach dono
	coachID    string
	otherCoach string // token de outro coach do mesmo tenant
	student    string // token do aluno (sub = studentID)
	studentID  string
	foreign    string // token de coach de outro tenant
	exerciseID string
}

func builderFixture(t *testing.T) builderActors {
	t.Helper()
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	handler := newTestRouterWithPool(t, publicPEM, pool)

	tenantA, tenantB := uuid.NewString(), uuid.NewString()
	coachID, otherCoachID, studentID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	expires := time.Now().Add(time.Minute)

	actors := builderActors{
		handler:    handler,
		tenantA:    tenantA,
		coach:      signTokenAs(t, priv, tenantA, coachID, []string{"coach"}, expires),
		coachID:    coachID,
		otherCoach: signTokenAs(t, priv, tenantA, otherCoachID, []string{"coach"}, expires),
		student:    signTokenAs(t, priv, tenantA, studentID, []string{"student"}, expires),
		studentID:  studentID,
		foreign:    signTokenAs(t, priv, tenantB, uuid.NewString(), []string{"coach"}, expires),
	}

	// O plano precisa de um exercício de verdade: o Aceite usa a biblioteca
	// global seedada (P1.3), a mesma que o coach veria na tela.
	actors.exerciseID = requireSeededLibrary(t, handler, actors.coach).ID
	return actors
}

// draftBody monta o payload do builder com os dias pedidos.
func draftBody(exerciseID string, labels ...string) map[string]any {
	days := make([]map[string]any, 0, len(labels))
	for _, label := range labels {
		days = append(days, map[string]any{
			"label": label,
			"title": "Treino " + label,
			"blocks": []map[string]any{{
				"block_type":   "superset",
				"rest_seconds": 90,
				"exercises": []map[string]any{{
					"exercise_id": exerciseID,
					"notes":       "cadência 2010",
					"sets": []map[string]any{
						{"reps_min": 8, "reps_max": 12, "target_load_kg": 40, "rest_seconds": 60},
						{"reps_min": 8, "reps_max": 10, "target_unit": "rpe", "target_value": 8, "rest_seconds": 60},
					},
				}},
			}},
		})
	}
	return map[string]any{"days": days}
}

func decodePlanBody(t *testing.T, raw []byte) apiPlan {
	t.Helper()
	var plan apiPlan
	if err := json.Unmarshal(raw, &plan); err != nil {
		t.Fatalf("decodificar plano: %v (%s)", err, raw)
	}
	return plan
}

// TestBuilderHappyPath é o Aceite do P1.4 ponta a ponta pela API: o coach cria
// o plano, salva a árvore A/B com sets estruturados, publica, e o aluno lê o
// plano dele em GET /v1/me/plan.
func TestBuilderHappyPath(t *testing.T) {
	a := builderFixture(t)

	rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.coach, map[string]any{
		"student_id": a.studentID, "title": "Hipertrofia A/B",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar plano: %d %s", rec.Code, rec.Body.String())
	}
	plan := decodePlanBody(t, rec.Body.Bytes())
	if plan.Status != "draft" || plan.Version != nil || plan.CoachID != a.coachID {
		t.Fatalf("plano recém-criado veio errado: %+v", plan)
	}

	rec = do(t, a.handler, http.MethodPut, "/v1/plans/"+plan.ID+"/draft", a.coach, draftBody(a.exerciseID, "A", "B"))
	if rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	draft := decodePlanBody(t, rec.Body.Bytes())
	if draft.Version == nil || !draft.Version.IsDraft || draft.Version.VersionNo != 1 {
		t.Fatalf("esperava rascunho v1, veio %+v", draft.Version)
	}
	if len(draft.Version.Days) != 2 {
		t.Fatalf("esperava 2 dias, veio %d", len(draft.Version.Days))
	}
	firstSet := draft.Version.Days[0].Blocks[0].Exercises[0].Sets[0]
	if firstSet.SetNo != 1 || *firstSet.RepsMin != 8 || *firstSet.RepsMax != 12 || *firstSet.TargetLoadKg != 40 {
		t.Fatalf("prescrição estruturada não voltou íntegra: %+v", firstSet)
	}
	secondSet := draft.Version.Days[0].Blocks[0].Exercises[0].Sets[1]
	if secondSet.TargetUnit != "rpe" || secondSet.TargetValue == nil || *secondSet.TargetValue != 8 {
		t.Fatalf("alvo relativo não voltou íntegro: %+v", secondSet)
	}
	// O nome do exercício vem resolvido no locale — o builder não precisa de
	// uma segunda chamada à biblioteca para desenhar a tela.
	summary := draft.Version.Days[0].Blocks[0].Exercises[0].Exercise
	if summary == nil || summary.Name == "" || !summary.IsGlobal {
		t.Fatalf("resumo do exercício não veio: %+v", summary)
	}

	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+plan.ID+"/publish", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}
	published := decodePlanBody(t, rec.Body.Bytes())
	if published.Version == nil || published.Version.IsDraft || published.Status != "published" {
		t.Fatalf("plano deveria sair publicado: %+v", published)
	}
	if published.ActiveVersionID != published.Version.ID || published.NextDayID != published.Version.Days[0].ID {
		t.Fatalf("rotação deveria apontar para o dia A da versão publicada: %+v", published)
	}

	// O aluno lê o próprio plano; o payload é o mesmo do builder.
	rec = do(t, a.handler, http.MethodGet, "/v1/me/plan", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("aluno lendo o plano: %d %s", rec.Code, rec.Body.String())
	}
	mine := decodePlanBody(t, rec.Body.Bytes())
	if mine.ID != plan.ID || mine.Version == nil || mine.Version.IsDraft {
		t.Fatalf("aluno deveria ver a versão publicada: %+v", mine)
	}
	if len(mine.Version.Days) != 2 || mine.Version.Days[0].Label != "A" {
		t.Fatalf("dias do aluno vieram errados: %+v", mine.Version.Days)
	}
	if mine.NextDayID != mine.Version.Days[0].ID {
		t.Fatalf("aluno deveria começar pelo dia A, veio %q", mine.NextDayID)
	}

	// Lista do coach: um plano ativo, publicado na v1, sem rascunho aberto.
	rec = do(t, a.handler, http.MethodGet, "/v1/students/"+a.studentID+"/plans", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("listar planos do aluno: %d %s", rec.Code, rec.Body.String())
	}
	var list apiPlanList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decodificar lista: %v", err)
	}
	if len(list.Items) != 1 || !list.Items[0].IsActive || list.Items[0].PublishedVersionNo != 1 || list.Items[0].HasDraft {
		t.Fatalf("resumo do plano veio errado: %+v", list.Items)
	}
}

// TestBuilderRepublishCreatesV2 é a segunda metade do Aceite: editar o
// rascunho e republicar gera a v2 sem tocar na v1.
func TestBuilderRepublishCreatesV2(t *testing.T) {
	a := builderFixture(t)
	planID := createPublishedPlan(t, a)

	edited := draftBody(a.exerciseID, "A", "B", "C")
	edited["title"] = "Hipertrofia A/B/C"
	rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, edited)
	if rec.Code != http.StatusOK {
		t.Fatalf("editar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	draft := decodePlanBody(t, rec.Body.Bytes())
	if draft.Version.VersionNo != 2 || !draft.Version.IsDraft {
		t.Fatalf("esperava rascunho v2, veio %+v", draft.Version)
	}

	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("publicar v2: %d %s", rec.Code, rec.Body.String())
	}

	// A v1 continua com dois dias e o conteúdo original.
	rec = do(t, a.handler, http.MethodGet, "/v1/plans/"+planID+"?version=1", a.coach, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("ler v1: %d %s", rec.Code, rec.Body.String())
	}
	v1 := decodePlanBody(t, rec.Body.Bytes())
	if v1.Version.VersionNo != 1 || v1.Version.IsDraft || len(v1.Version.Days) != 2 {
		t.Fatalf("v1 deveria ficar congelada com 2 dias: %+v", v1.Version)
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/me/plan", a.student, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("aluno lendo plano: %d %s", rec.Code, rec.Body.String())
	}
	mine := decodePlanBody(t, rec.Body.Bytes())
	if mine.Version.VersionNo != 2 || len(mine.Version.Days) != 3 || mine.Title != "Hipertrofia A/B/C" {
		t.Fatalf("aluno deveria ver a v2 com 3 dias: %+v", mine)
	}
}

// TestPublishIncompleteIsRejected: plano sem dia/bloco/set não publica.
func TestPublishIncompleteIsRejected(t *testing.T) {
	a := builderFixture(t)
	planID := createPlan(t, a, a.coach)

	rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, map[string]any{"days": []any{}})
	if rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho vazio: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil)
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("esperava 422, veio %d %s", rec.Code, rec.Body.String())
	}
	if code := decodeError(t, rec).Code; code != "plan_incomplete" {
		t.Fatalf("esperava plan_incomplete, veio %q", code)
	}

	// Publicar de novo, agora completo, e uma terceira vez sem rascunho.
	rec = do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, draftBody(a.exerciseID, "A"))
	if rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil)
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "no_draft_to_publish" {
		t.Fatalf("esperava 409 no_draft_to_publish, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestPlanAccessControl cobre quem pode o quê: outro tenant não vê o plano,
// outro coach do tenant segue o linker (vínculo), e o aluno não cria plano nenhum.
func TestPlanAccessControl(t *testing.T) {
	a := builderFixture(t)
	planID := createPublishedPlan(t, a)

	if rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+planID, a.foreign, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("coach de outro tenant deveria receber 404, veio %d", rec.Code)
	}
	if rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+planID, a.otherCoach, nil); rec.Code != http.StatusOK {
		t.Fatalf("outro coach do tenant deveria ler o plano, veio %d", rec.Code)
	}
	// O vínculo coach↔aluno (ADR-016) é checado pelo linker; aqui ele libera
	// todo mundo, então outro coach edita. O cross-coach de verdade está em
	// coach_link_test.go.
	rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.otherCoach, draftBody(a.exerciseID, "A"))
	if rec.Code != http.StatusOK {
		t.Fatalf("coach vinculado deveria editar o plano, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/plans", a.student, map[string]any{
		"student_id": a.studentID, "title": "Meu próprio treino",
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não deveria criar plano, veio %d", rec.Code)
	}
	// Aluno sem plano publicado: 404, não 500.
	a2 := builderFixture(t)
	if rec := do(t, a2.handler, http.MethodGet, "/v1/me/plan", a2.student, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("aluno sem plano deveria receber 404, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestDraftValidation cobre as recusas do payload do builder, incluindo o
// exercício de outro tenant (que a FK sozinha deixaria passar).
func TestDraftValidation(t *testing.T) {
	a := builderFixture(t)
	planID := createPlan(t, a, a.coach)

	foreignExercise := uuid.NewString()
	cases := []struct {
		name     string
		body     any
		status   int
		wantCode string
	}{
		{"corpo inválido", "não é json", http.StatusBadRequest, "invalid_body"},
		{"rótulo duplicado", map[string]any{"days": []map[string]any{
			{"label": "A", "blocks": []any{}}, {"label": "A", "blocks": []any{}},
		}}, http.StatusBadRequest, "validation_error"},
		{"rótulo vazio", map[string]any{"days": []map[string]any{{"label": "  "}}}, http.StatusBadRequest, "validation_error"},
		{"tipo de bloco inválido", map[string]any{"days": []map[string]any{{
			"label": "A", "blocks": []map[string]any{{"block_type": "piramide"}},
		}}}, http.StatusBadRequest, "validation_error"},
		{"reps invertidas", map[string]any{"days": []map[string]any{{
			"label": "A", "blocks": []map[string]any{{"exercises": []map[string]any{{
				"exercise_id": a.exerciseID,
				"sets":        []map[string]any{{"reps_min": 12, "reps_max": 8}},
			}}}},
		}}}, http.StatusBadRequest, "validation_error"},
		{"rpe sem valor", map[string]any{"days": []map[string]any{{
			"label": "A", "blocks": []map[string]any{{"exercises": []map[string]any{{
				"exercise_id": a.exerciseID,
				"sets":        []map[string]any{{"target_unit": "rpe"}},
			}}}},
		}}}, http.StatusBadRequest, "validation_error"},
		{"exercício inexistente", map[string]any{"days": []map[string]any{{
			"label": "A", "blocks": []map[string]any{{"exercises": []map[string]any{{
				"exercise_id": foreignExercise,
				"sets":        []map[string]any{{"reps_min": 10}},
			}}}},
		}}}, http.StatusUnprocessableEntity, "unknown_exercise"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, tc.body)
			if rec.Code != tc.status {
				t.Fatalf("esperava %d, veio %d %s", tc.status, rec.Code, rec.Body.String())
			}
			if code := decodeError(t, rec).Code; code != tc.wantCode {
				t.Fatalf("esperava code %q, veio %q", tc.wantCode, code)
			}
		})
	}

	t.Run("plano inexistente", func(t *testing.T) {
		rec := do(t, a.handler, http.MethodGet, "/v1/plans/"+uuid.NewString(), a.coach, nil)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("esperava 404, veio %d", rec.Code)
		}
	})
	t.Run("aluno inválido na criação", func(t *testing.T) {
		rec := do(t, a.handler, http.MethodPost, "/v1/plans", a.coach, map[string]any{
			"student_id": "não-é-uuid", "title": "X",
		})
		if rec.Code != http.StatusBadRequest || decodeError(t, rec).Params["field"] != "student_id" {
			t.Fatalf("esperava validation_error em student_id, veio %d %s", rec.Code, rec.Body.String())
		}
	})
}

func createPlan(t *testing.T, a builderActors, token string) string {
	t.Helper()
	rec := do(t, a.handler, http.MethodPost, "/v1/plans", token, map[string]any{
		"student_id": a.studentID, "title": "Hipertrofia A/B",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar plano: %d %s", rec.Code, rec.Body.String())
	}
	return decodePlanBody(t, rec.Body.Bytes()).ID
}

func createPublishedPlan(t *testing.T, a builderActors) string {
	t.Helper()
	planID := createPlan(t, a, a.coach)
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, draftBody(a.exerciseID, "A", "B")); rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}
	return planID
}
