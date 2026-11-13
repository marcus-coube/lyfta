package http_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type apiVariation struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	ArchivedAt  *string `json:"archived_at"`
}

func createVariation(t *testing.T, a builderActors, token, name, description string) apiVariation {
	t.Helper()
	rec := do(t, a.handler, http.MethodPost, "/v1/variations", token, map[string]any{"name": name, "description": description})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar variação: %d %s", rec.Code, rec.Body.String())
	}
	return decodeInto[apiVariation](t, rec.Body.Bytes())
}

func listVariations(t *testing.T, a builderActors, token, query string) []apiVariation {
	t.Helper()
	rec := do(t, a.handler, http.MethodGet, "/v1/variations"+query, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("listar variações: %d %s", rec.Code, rec.Body.String())
	}
	return decodeInto[struct {
		Items []apiVariation `json:"items"`
	}](t, rec.Body.Bytes()).Items
}

// TestVariationCRUD: caminho feliz do cadastro, nome repetido (409, sem
// diferenciar caixa), arquivar libera o nome e some do filtro padrão, e a
// variação de um tenant é invisível (404) para outro.
func TestVariationCRUD(t *testing.T) {
	a := builderFixture(t)
	v := createVariation(t, a, a.coach, "Pausa no fundo", "Segure 2 s embaixo.")

	rec := do(t, a.handler, http.MethodPost, "/v1/variations", a.otherCoach, map[string]any{"name": "pausa NO fundo"})
	if rec.Code != http.StatusConflict || decodeError(t, rec).Code != "variation_name_taken" {
		t.Fatalf("nome repetido deveria ser 409 variation_name_taken: %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, a.handler, http.MethodPost, "/v1/variations", a.coach, map[string]any{"name": strings.Repeat("a", 41)})
	if rec.Code != http.StatusBadRequest || decodeError(t, rec).Code != "validation_error" {
		t.Fatalf("nome de 41 caracteres deveria ser validation_error: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodPut, "/v1/variations/"+v.ID, a.otherCoach, map[string]any{"name": "Pausa 2s", "description": "x"})
	if rec.Code != http.StatusOK || decodeInto[apiVariation](t, rec.Body.Bytes()).Name != "Pausa 2s" {
		t.Fatalf("outro coach do tenant edita (conteúdo do tenant): %d %s", rec.Code, rec.Body.String())
	}

	if rec = do(t, a.handler, http.MethodPost, "/v1/variations/"+v.ID+"/archive", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("arquivar: %d %s", rec.Code, rec.Body.String())
	}
	if rec = do(t, a.handler, http.MethodPost, "/v1/variations/"+v.ID+"/archive", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("arquivar é idempotente: %d", rec.Code)
	}
	if got := listVariations(t, a, a.coach, ""); len(got) != 0 {
		t.Fatalf("arquivada não entra no status=active: %+v", got)
	}
	if got := listVariations(t, a, a.coach, "?status=archived&q=pausa"); len(got) != 1 || got[0].ArchivedAt == nil {
		t.Fatalf("status=archived deveria listar a variação: %+v", got)
	}
	if got := listVariations(t, a, a.coach, "?status=all"); len(got) != 1 {
		t.Fatalf("status=all: %+v", got)
	}
	// Arquivar liberou o nome; reativar agora conflita com a nova.
	createVariation(t, a, a.coach, "Pausa 2s", "")
	rec = do(t, a.handler, http.MethodPost, "/v1/variations/"+v.ID+"/unarchive", a.coach, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("reativar com nome ocupado: %d %s", rec.Code, rec.Body.String())
	}

	// Outro tenant: lista vazia, e editar/arquivar é 404.
	if got := listVariations(t, a, a.foreign, "?status=all"); len(got) != 0 {
		t.Fatalf("tenant B não enxerga variações do A: %+v", got)
	}
	for _, c := range []struct{ method, path string }{
		{http.MethodPut, "/v1/variations/" + v.ID},
		{http.MethodPost, "/v1/variations/" + v.ID + "/archive"},
		{http.MethodPost, "/v1/variations/" + v.ID + "/unarchive"},
	} {
		if rec = do(t, a.handler, c.method, c.path, a.foreign, map[string]any{"name": "invasão"}); rec.Code != http.StatusNotFound {
			t.Fatalf("%s %s de outro tenant deveria ser 404: %d", c.method, c.path, rec.Code)
		}
	}
	// Aluno não acessa o cadastro.
	if rec = do(t, a.handler, http.MethodGet, "/v1/variations", a.student, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("aluno deveria receber 403: %d", rec.Code)
	}
}

func variationBody(exerciseID, firstSet, secondSet string) map[string]any {
	set := func(id string) map[string]any {
		s := map[string]any{"reps_min": 8, "reps_max": 10}
		if id != "" {
			s["variation_id"] = id
		}
		return s
	}
	return map[string]any{"days": []map[string]any{{
		"label": "A",
		"blocks": []map[string]any{{
			"block_type": "straight", "rest_seconds": 60,
			"exercises": []map[string]any{{
				"exercise_id": exerciseID, "sets": []map[string]any{set(firstSet), set(secondSet)},
			}},
		}},
	}}}
}

type apiVariationSets struct {
	Version struct {
		Days []struct {
			Blocks []struct {
				Exercises []struct {
					Sets []struct {
						Variation *apiVariation `json:"variation"`
					} `json:"sets"`
				} `json:"exercises"`
			} `json:"blocks"`
		} `json:"days"`
	} `json:"version"`
	Day *struct {
		Blocks []struct {
			Exercises []struct {
				Sets []struct {
					Variation *apiVariation `json:"variation"`
				} `json:"sets"`
			} `json:"exercises"`
		} `json:"blocks"`
	} `json:"day"`
}

// TestVariationReachesPlanAndToday: a variação vai da prescrição ao GET do
// plano e ao /me/today do aluno, que nunca chama /v1/variations.
func TestVariationReachesPlanAndToday(t *testing.T) {
	a := builderFixture(t)
	v := createVariation(t, a, a.coach, "Pausa no fundo", "Segure 2 s embaixo.")
	planID := createPlan(t, a, a.coach)

	rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, variationBody(a.exerciseID, "", v.ID))
	if rec.Code != http.StatusOK {
		t.Fatalf("salvar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	if rec = do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/plans/"+planID, a.coach, nil)
	var plan apiVariationSets
	if err := json.Unmarshal(rec.Body.Bytes(), &plan); err != nil {
		t.Fatalf("decodificar plano: %v", err)
	}
	sets := plan.Version.Days[0].Blocks[0].Exercises[0].Sets
	if sets[0].Variation != nil || sets[1].Variation == nil || sets[1].Variation.ID != v.ID ||
		sets[1].Variation.Name != "Pausa no fundo" || sets[1].Variation.Description != "Segure 2 s embaixo." {
		t.Fatalf("variação não voltou no GET do plano: %s", rec.Body.String())
	}

	rec = do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil)
	var today apiVariationSets
	if err := json.Unmarshal(rec.Body.Bytes(), &today); err != nil || today.Day == nil {
		t.Fatalf("decodificar /me/today: %v %s", err, rec.Body.String())
	}
	ts := today.Day.Blocks[0].Exercises[0].Sets
	if ts[0].Variation != nil || ts[1].Variation == nil ||
		ts[1].Variation.Name != "Pausa no fundo" || ts[1].Variation.Description != "Segure 2 s embaixo." {
		t.Fatalf("variação não chegou ao /me/today: %s", rec.Body.String())
	}
}

// TestVariationArchivedAndUnknownInDraft: arquivada recusada em série nova
// (422 variation_not_found), mas a série que já a usava continua salvando;
// id de outro tenant ou inexistente é sempre 422; id malformado é 400.
func TestVariationArchivedAndUnknownInDraft(t *testing.T) {
	a := builderFixture(t)
	v := createVariation(t, a, a.coach, "Pausa no fundo", "")
	foreignVar := func() string {
		rec := do(t, a.handler, http.MethodPost, "/v1/variations", a.foreign, map[string]any{"name": "Do outro tenant"})
		if rec.Code != http.StatusCreated {
			t.Fatalf("criar variação do tenant B: %d %s", rec.Code, rec.Body.String())
		}
		return decodeInto[apiVariation](t, rec.Body.Bytes()).ID
	}()
	planID := createPlan(t, a, a.coach)
	save := func(body map[string]any) *httptest.ResponseRecorder {
		return do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach, body)
	}

	if rec := save(variationBody(a.exerciseID, v.ID, "")); rec.Code != http.StatusOK {
		t.Fatalf("salvar com variação ativa: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/variations/"+v.ID+"/archive", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("arquivar: %d", rec.Code)
	}

	// A série que já apontava para ela segue salvando (v2 do plano).
	if rec := save(variationBody(a.exerciseID, v.ID, "")); rec.Code != http.StatusOK {
		t.Fatalf("série existente com variação arquivada deveria salvar: %d %s", rec.Code, rec.Body.String())
	}
	// Uma segunda série com a arquivada é série nova: recusada.
	rec := save(variationBody(a.exerciseID, v.ID, v.ID))
	if e := decodeError(t, rec); rec.Code != http.StatusUnprocessableEntity || e.Code != "variation_not_found" {
		t.Fatalf("série nova com arquivada deveria ser 422 variation_not_found: %d %s", rec.Code, rec.Body.String())
	}
	// Variação de outro tenant (a FK sozinha deixaria passar).
	rec = save(variationBody(a.exerciseID, foreignVar, ""))
	if e := decodeError(t, rec); rec.Code != http.StatusUnprocessableEntity || e.Code != "variation_not_found" {
		t.Fatalf("variação de outro tenant deveria ser 422: %d %s", rec.Code, rec.Body.String())
	}
	rec = save(variationBody(a.exerciseID, "00000000-0000-4000-8000-000000000000", ""))
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("variação inexistente deveria ser 422: %d", rec.Code)
	}
	rec = save(variationBody(a.exerciseID, "não-é-uuid", ""))
	if e := decodeError(t, rec); rec.Code != http.StatusBadRequest || e.Code != "validation_error" {
		t.Fatalf("id malformado deveria ser 400 validation_error: %d %s", rec.Code, rec.Body.String())
	}
}
