package http_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/coachlink"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

type overviewBody struct {
	Items []struct {
		StudentID     string  `json:"student_id"`
		LastSessionAt *string `json:"last_session_at"`
		ActivePlan    *struct {
			ID        string `json:"id"`
			Title     string `json:"title"`
			VersionNo int    `json:"version_no"`
		} `json:"active_plan"`
	} `json:"items"`
}

// TestStudentsOverview cobre o resumo em lote: coach só recebe os vinculados
// (os demais ids somem), owner recebe todos, aluno sem plano/treino vem com
// nulos, validação do teto e do formato.
func TestStudentsOverview(t *testing.T) {
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	identity := newFakeIdentity(t)
	handler := newTestRouterWithLinker(t, publicPEM, pool, coachlink.NewClient(identity.server.URL, testInternalToken, 0))

	tenant := uuid.NewString()
	coachA, coachB, owner := uuid.NewString(), uuid.NewString(), uuid.NewString()
	trained, idle, foreign := uuid.NewString(), uuid.NewString(), uuid.NewString()
	identity.assign(coachA, trained, idle)
	identity.assign(coachB, foreign)
	expires := time.Now().Add(time.Minute)
	tokA := signTokenAs(t, priv, tenant, coachA, []string{"coach"}, expires)
	tokOwner := signTokenAs(t, priv, tenant, owner, []string{"owner", "coach"}, expires)
	tokStudent := signTokenAs(t, priv, tenant, trained, []string{"student"}, expires)

	exerciseID := requireSeededLibrary(t, handler, tokA).ID
	rec := do(t, handler, http.MethodPost, "/v1/plans", tokA, map[string]any{"student_id": trained, "title": "Plano A"})
	planID := decodePlanBody(t, rec.Body.Bytes()).ID
	do(t, handler, http.MethodPut, "/v1/plans/"+planID+"/draft", tokA, draftBody(exerciseID, "A"))
	if rec := do(t, handler, http.MethodPost, "/v1/plans/"+planID+"/publish", tokA, nil); rec.Code != http.StatusOK {
		t.Fatalf("publicar: %d %s", rec.Code, rec.Body.String())
	}
	// Uma sessão recebida pelo servidor (insert direto: o contrato de sync é
	// testado em sync_test.go).
	if err := repo.WithTenant(t.Context(), pool, tenant, func(tx pgx.Tx) error {
		_, err := tx.Exec(t.Context(), `
			INSERT INTO workout_sessions (id, tenant_id, student_id, plan_version_id, day_id, snapshot, client_id, received_at)
			SELECT $1, $2, $3, v.id, d.id, '{}'::jsonb, $4, '2026-11-01T12:00:00Z'
			FROM workout_plan_versions v JOIN workout_days d ON d.plan_version_id = v.id
			WHERE v.plan_id = $5 AND v.published_at IS NOT NULL LIMIT 1`,
			uuid.NewString(), tenant, trained, uuid.NewString(), planID)
		return err
	}); err != nil {
		t.Fatalf("inserir sessão: %v", err)
	}

	ids := []string{trained, idle, foreign}
	rec = do(t, handler, http.MethodPost, "/v1/students/overview", tokA, map[string]any{"student_ids": ids})
	if rec.Code != http.StatusOK {
		t.Fatalf("coach: %d %s", rec.Code, rec.Body.String())
	}
	var got overviewBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Items) != 2 {
		t.Fatalf("coach deveria ver 2 (o aluno de B some): %s", rec.Body.String())
	}
	byID := map[string]int{}
	for i, it := range got.Items {
		byID[it.StudentID] = i
	}
	tr := got.Items[byID[trained]]
	if tr.ActivePlan == nil || tr.ActivePlan.ID != planID || tr.ActivePlan.Title != "Plano A" || tr.ActivePlan.VersionNo != 1 {
		t.Errorf("plano ativo: %+v", tr.ActivePlan)
	}
	if tr.LastSessionAt == nil || *tr.LastSessionAt != "2026-11-01T12:00:00Z" {
		t.Errorf("último treino: %v", tr.LastSessionAt)
	}
	id := got.Items[byID[idle]]
	if id.ActivePlan != nil || id.LastSessionAt != nil {
		t.Errorf("aluno sem plano/treino deveria vir nulo: %+v", id)
	}

	rec = do(t, handler, http.MethodPost, "/v1/students/overview", tokOwner, map[string]any{"student_ids": ids})
	var all overviewBody
	_ = json.Unmarshal(rec.Body.Bytes(), &all)
	if rec.Code != http.StatusOK || len(all.Items) != 3 {
		t.Errorf("owner vê todos: %d %s", rec.Code, rec.Body.String())
	}

	// Outro tenant não enxerga nada (RLS), mesmo sendo owner.
	tokOther := signTokenAs(t, priv, uuid.NewString(), owner, []string{"owner"}, expires)
	rec = do(t, handler, http.MethodPost, "/v1/students/overview", tokOther, map[string]any{"student_ids": []string{trained}})
	var other overviewBody
	_ = json.Unmarshal(rec.Body.Bytes(), &other)
	if len(other.Items) != 1 || other.Items[0].ActivePlan != nil || other.Items[0].LastSessionAt != nil {
		t.Errorf("cross-tenant não pode vazar dados: %s", rec.Body.String())
	}

	if rec := do(t, handler, http.MethodPost, "/v1/students/overview", tokStudent, map[string]any{"student_ids": ids}); rec.Code != http.StatusForbidden {
		t.Errorf("aluno: esperava 403, veio %d", rec.Code)
	}
	if rec := do(t, handler, http.MethodPost, "/v1/students/overview", tokA, map[string]any{"student_ids": []string{}}); rec.Code != http.StatusUnprocessableEntity && rec.Code != http.StatusBadRequest {
		t.Errorf("lista vazia: %d", rec.Code)
	}
	tooMany := make([]string, 101)
	for i := range tooMany {
		tooMany[i] = uuid.NewString()
	}
	if rec := do(t, handler, http.MethodPost, "/v1/students/overview", tokA, map[string]any{"student_ids": tooMany}); rec.Code == http.StatusOK {
		t.Errorf("101 ids deveria ser rejeitado")
	}
}
