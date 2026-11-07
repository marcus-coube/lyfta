package http_test

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// inviteCoach convida e aceita um coach (sem owner) e devolve token e id.
func inviteCoach(t *testing.T, f usersFixture, ownerToken, name string) (token, id string) {
	t.Helper()
	email := uniqueEmail("coach")
	resp := doPostAuth(t, f.client, f.url+"/v1/invitations", ownerToken, map[string]any{
		"email": email, "role": "coach", "name": name,
	})
	if resp.status != http.StatusCreated {
		t.Fatalf("convidar coach: %d %+v", resp.status, resp.body)
	}
	msg, _ := f.mailer.lastTo(email)
	accept := doPost(t, f.client, f.url+"/v1/invitations/accept", map[string]any{
		"token": tokenFromMail(t, msg), "password": "SenhaCoach123!", "terms_version": testTermsVersion,
	})
	if accept.status != http.StatusOK {
		t.Fatalf("aceitar convite do coach: %d %+v", accept.status, accept.body)
	}
	return accept.body["access_token"].(string), accept.body["user_id"].(string)
}

// studentIDByName acha o id do aluno na lista (visão do token dado).
func studentIDByName(t *testing.T, f usersFixture, token, name string) string {
	t.Helper()
	list := doGetAuth(t, f.client, f.url+"/v1/users?role=student", token)
	for _, raw := range list.body["items"].([]any) {
		item := raw.(map[string]any)
		if item["name"] == name {
			return item["id"].(string)
		}
	}
	t.Fatalf("aluno %q não está na lista: %+v", name, list.body)
	return ""
}

func ownerUserID(t *testing.T, f usersFixture) string {
	t.Helper()
	list := doGetAuth(t, f.client, f.url+"/v1/users?role=owner", f.coachToken)
	return list.body["items"].([]any)[0].(map[string]any)["id"].(string)
}

// internalGet chama um endpoint M2M com (ou sem) o token interno.
func internalGet(t *testing.T, f usersFixture, path string, withToken bool) jsonResponse {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, f.url+path, nil)
	if withToken {
		req.Header.Set("X-Internal-Token", testInternalToken)
	}
	resp, err := f.client.Do(req)
	if err != nil {
		t.Fatalf("GET %s: %v", path, err)
	}
	defer resp.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if body == nil {
		body = map[string]any{}
	}
	return jsonResponse{status: resp.StatusCode, body: body}
}

// tenantIDOf lê o tenant_id do payload do access token (sem verificar a
// assinatura: o teste só precisa do valor).
func tenantIDOf(t *testing.T, f usersFixture) string {
	t.Helper()
	parts := strings.Split(f.coachToken, ".")
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("payload do token: %v", err)
	}
	var claims struct {
		TenantID string `json:"tenant_id"`
	}
	if err := json.Unmarshal(raw, &claims); err != nil {
		t.Fatalf("claims: %v", err)
	}
	return claims.TenantID
}

// TestCoachLinkListScopeAndReassign cobre o Aceite do P4.7 no identity: o
// convite vincula, o coach só vê os seus, o owner vê todos, filtra e
// reatribui, e a reatribuição vale na lista e no M2M.
func TestCoachLinkListScopeAndReassign(t *testing.T) {
	f := newUsersFixture(t)
	coachB, coachBID := inviteCoach(t, f, f.coachToken, "Coach B")

	inviteStudent(t, f, f.coachToken, "Aluno do Owner")
	inviteStudent(t, f, coachB, "Aluno do B")

	// Coach B (sem owner) só vê o aluno dele.
	own := doGetAuth(t, f.client, f.url+"/v1/users?role=student", coachB)
	if names := userNames(t, own); len(names) != 1 || names[0] != "Aluno do B" {
		t.Fatalf("coach B deveria ver só o aluno dele: %v", names)
	}
	// Sem role, vale o mesmo (nunca devolve aluno de outro).
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/users", coachB)); len(names) != 1 || names[0] != "Aluno do B" {
		t.Fatalf("lista sem filtro do coach B: %v", names)
	}
	// O diretório de professores segue aberto (nomes do chat, sem dado de aluno).
	if resp := doGetAuth(t, f.client, f.url+"/v1/users?role=coach", coachB); resp.status != http.StatusOK {
		t.Fatalf("coach lista coaches: esperava 200, obtive %d", resp.status)
	}

	// Owner vê todos, com o professor de cada um, e filtra por coach_id.
	all := doGetAuth(t, f.client, f.url+"/v1/users?role=student", f.coachToken)
	if names := userNames(t, all); len(names) != 2 {
		t.Fatalf("owner deveria ver os 2 alunos: %v", names)
	}
	for _, raw := range all.body["items"].([]any) {
		item := raw.(map[string]any)
		want := "Coach Responsável"
		if item["name"] == "Aluno do B" {
			want = "Coach B"
		}
		if item["coach_name"] != want {
			t.Fatalf("coach_name de %v: %v (esperava %s)", item["name"], item["coach_name"], want)
		}
	}
	filtered := doGetAuth(t, f.client, f.url+"/v1/users?role=student&coach_id="+coachBID, f.coachToken)
	if names := userNames(t, filtered); len(names) != 1 || names[0] != "Aluno do B" {
		t.Fatalf("filtro coach_id: %v", names)
	}

	studentB := studentIDByName(t, f, f.coachToken, "Aluno do B")
	tenantID := tenantIDOf(t, f)

	// M2M: exige token interno; devolve o conjunto e o coach.
	if resp := internalGet(t, f, "/internal/v1/coaches/"+coachBID+"/students?tenant_id="+tenantID, false); resp.status != http.StatusUnauthorized {
		t.Fatalf("M2M sem token: %d", resp.status)
	}
	set := internalGet(t, f, "/internal/v1/coaches/"+coachBID+"/students?tenant_id="+tenantID, true)
	if ids := stringList(set.body["student_ids"]); len(ids) != 1 || ids[0] != studentB {
		t.Fatalf("student_ids do coach B: %+v", set.body)
	}
	who := internalGet(t, f, "/internal/v1/students/"+studentB+"/coach?tenant_id="+tenantID, true)
	if who.body["coach_id"] != coachBID {
		t.Fatalf("coach do aluno: %+v", who.body)
	}

	// Só owner reatribui.
	put := func(token, student, coach string) jsonResponse {
		return doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/students/"+student+"/coach", token, map[string]string{"coach_id": coach})
	}
	if resp := put(coachB, studentB, coachBID); resp.status != http.StatusForbidden {
		t.Fatalf("coach reatribuindo: esperava 403, obtive %d", resp.status)
	}
	// Alvos inválidos: coach que é aluno, aluno que é coach, id inexistente.
	if resp := put(f.coachToken, studentB, studentB); resp.status != http.StatusUnprocessableEntity || resp.body["code"] != "validation_error" {
		t.Fatalf("coach inválido: %d %+v", resp.status, resp.body)
	}
	if resp := put(f.coachToken, coachBID, coachBID); resp.status != http.StatusUnprocessableEntity {
		t.Fatalf("alvo que não é aluno: %d", resp.status)
	}
	if resp := put(f.coachToken, "01a1b424-0000-7000-8000-000000000000", coachBID); resp.status != http.StatusUnprocessableEntity {
		t.Fatalf("aluno inexistente: %d", resp.status)
	}

	// Reatribuir ao owner: o B perde o aluno, a lista e o M2M refletem.
	ownerID := ownerUserID(t, f)
	if resp := put(f.coachToken, studentB, ownerID); resp.status != http.StatusOK {
		t.Fatalf("reatribuir: %d %+v", resp.status, resp.body)
	}
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/users?role=student", coachB)); len(names) != 0 {
		t.Fatalf("coach B deveria ficar sem alunos: %v", names)
	}
	who = internalGet(t, f, "/internal/v1/students/"+studentB+"/coach?tenant_id="+tenantID, true)
	if who.body["coach_id"] != ownerID {
		t.Fatalf("coach atual após reatribuir: %+v", who.body)
	}
}

// TestDeleteCoachReturnsStudentsToOwner: a exclusão de um coach não deixa
// aluno sem professor; a de um aluno apaga o vínculo.
func TestDeleteCoachReturnsStudentsToOwner(t *testing.T) {
	f := newUsersFixture(t)
	coachB, coachBID := inviteCoach(t, f, f.coachToken, "Coach Saindo")
	inviteStudent(t, f, coachB, "Aluno Órfão")
	studentID := studentIDByName(t, f, f.coachToken, "Aluno Órfão")
	tenantID := tenantIDOf(t, f)
	ownerID := ownerUserID(t, f)

	del := doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", coachB, map[string]string{"password": "SenhaCoach123!"})
	if del.status != http.StatusNoContent {
		t.Fatalf("excluir coach: %d %+v", del.status, del.body)
	}
	who := internalGet(t, f, "/internal/v1/students/"+studentID+"/coach?tenant_id="+tenantID, true)
	if who.status != http.StatusOK || who.body["coach_id"] != ownerID {
		t.Fatalf("aluno deveria voltar ao owner: %d %+v", who.status, who.body)
	}
	set := internalGet(t, f, "/internal/v1/coaches/"+coachBID+"/students?tenant_id="+tenantID, true)
	if ids := stringList(set.body["student_ids"]); len(ids) != 0 {
		t.Fatalf("coach excluído não pode ter alunos: %+v", set.body)
	}

	// Excluir o aluno apaga o vínculo (404 no M2M).
	session, _ := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	sid := session["user_id"].(string)
	if resp := internalGet(t, f, "/internal/v1/students/"+sid+"/coach?tenant_id="+tenantID, true); resp.status != http.StatusOK {
		t.Fatalf("aluno novo deveria ter vínculo: %d", resp.status)
	}
	doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", session["access_token"].(string), map[string]string{"password": "SenhaAluno123!"})
	if resp := internalGet(t, f, "/internal/v1/students/"+sid+"/coach?tenant_id="+tenantID, true); resp.status != http.StatusNotFound || resp.body["code"] != "student_not_found" {
		t.Fatalf("aluno excluído: %d %+v", resp.status, resp.body)
	}
}
