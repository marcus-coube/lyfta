package http_test

import (
	"net/http"
	"testing"
)

func statsOf(t *testing.T, f usersFixture, query, token string) map[string]any {
	t.Helper()
	resp := doGetAuth(t, f.client, f.url+"/v1/students/stats"+query, token)
	if resp.status != http.StatusOK {
		t.Fatalf("stats%s: %d %+v", query, resp.status, resp.body)
	}
	return resp.body
}

// TestStudentStats cobre o Aceite da P8.1 no identity: coach conta só o
// vínculo dele; owner conta tudo e filtra por `coach_id`; convite pendente e
// inativo entram nas faixas certas; coach_id inválido é 400.
func TestStudentStats(t *testing.T) {
	f := newUsersFixture(t)
	coachToken, coachID := inviteCoach(t, f, f.coachToken, "Coach Dois")

	// Owner: 2 alunos ativos (um vira inativo depois). Coach Dois: 1 ativo + 1 convidado.
	inviteStudent(t, f, f.coachToken, "Ana Alves")
	inviteStudent(t, f, f.coachToken, "Bia Braga")
	inviteStudent(t, f, coachToken, "Caio Costa")
	pendingEmail := uniqueEmail("pendente")
	if resp := doPostAuth(t, f.client, f.url+"/v1/invitations", coachToken, map[string]any{
		"email": pendingEmail, "role": "student", "name": "Duda Dias",
	}); resp.status != http.StatusCreated {
		t.Fatalf("convite pendente: %d %+v", resp.status, resp.body)
	}
	biaID := studentIDByName(t, f, f.coachToken, "Bia Braga")
	if resp := doJSONAuth(t, f.client, http.MethodPost, f.url+"/v1/students/"+biaID+"/deactivate", f.coachToken, nil); resp.status != http.StatusOK {
		t.Fatalf("inativar: %d %+v", resp.status, resp.body)
	}

	// Coach só vê o dele; ?coach_id= é ignorado para coach.
	mine := statsOf(t, f, "?coach_id="+ownerUserID(t, f), coachToken)
	if mine["active"] != float64(1) || mine["inactive"] != float64(0) || mine["pending_invites"] != float64(1) || mine["new_this_month"] != float64(2) {
		t.Fatalf("stats do coach: %+v", mine)
	}
	// Owner vê todos.
	all := statsOf(t, f, "", f.coachToken)
	if all["active"] != float64(2) || all["inactive"] != float64(1) || all["pending_invites"] != float64(1) || all["new_this_month"] != float64(4) {
		t.Fatalf("stats do owner: %+v", all)
	}
	// Owner filtra por professor.
	byCoach := statsOf(t, f, "?coach_id="+coachID, f.coachToken)
	if byCoach["active"] != float64(1) || byCoach["pending_invites"] != float64(1) || byCoach["inactive"] != float64(0) {
		t.Fatalf("stats filtradas: %+v", byCoach)
	}
	if resp := doGetAuth(t, f.client, f.url+"/v1/students/stats?coach_id=x", f.coachToken); resp.status != http.StatusBadRequest {
		t.Fatalf("coach_id inválido: %d %+v", resp.status, resp.body)
	}
	if resp := doGetAuth(t, f.client, f.url+"/v1/students/stats", ""); resp.status != http.StatusUnauthorized {
		t.Fatalf("sem token: %d", resp.status)
	}

	// M2M: ids dos alunos ativos (Ana, Caio; Bia inativa e Duda convidada ficam fora).
	tenantID := tenantIDOf(t, f)
	active := internalGet(t, f, "/internal/v1/students?tenant_id="+tenantID, true)
	if ids, _ := active.body["student_ids"].([]any); active.status != http.StatusOK || len(ids) != 2 {
		t.Fatalf("M2M ativos: %d %+v", active.status, active.body)
	}
	if resp := internalGet(t, f, "/internal/v1/students?tenant_id="+tenantID, false); resp.status != http.StatusUnauthorized {
		t.Fatalf("M2M sem token: %d", resp.status)
	}
	if resp := internalGet(t, f, "/internal/v1/students", true); resp.status != http.StatusBadRequest {
		t.Fatalf("M2M sem tenant: %d", resp.status)
	}
}
