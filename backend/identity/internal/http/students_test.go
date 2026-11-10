package http_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/google/uuid"
)

func studentLogin(t *testing.T, f usersFixture, email, password string) jsonResponse {
	t.Helper()
	return doPost(t, f.client, f.url+"/v1/auth/login", map[string]any{"email": email, "password": password})
}

// TestStudentLifecycle cobre o Aceite da P5.2: inativar bloqueia login e
// refresh e tira o aluno da lista padrão; reativar devolve o acesso; o
// histórico registra o aceite do convite e as duas transições; repetir a
// transição é 409.
func TestStudentLifecycle(t *testing.T) {
	f := newUsersFixture(t)
	email := inviteStudent(t, f, f.coachToken, "Ana Alves")
	studentID := studentIDByName(t, f, f.coachToken, "Ana Alves")
	tenantID := tenantIDOf(t, f)
	base := f.url + "/v1/students/" + studentID

	login := studentLogin(t, f, email, "SenhaAluno123!")
	if login.status != http.StatusOK {
		t.Fatalf("login do aluno ativo: %d %+v", login.status, login.body)
	}
	refresh := login.body["refresh_token"].(string)

	// Ficha: cadastro + coach + status.
	got := doGetAuth(t, f.client, base, f.coachToken)
	if got.status != http.StatusOK || got.body["status"] != "active" || got.body["coach_name"] != "Coach Responsável" {
		t.Fatalf("ficha: %d %+v", got.status, got.body)
	}

	// Inativar (com motivo).
	off := doJSONAuth(t, f.client, http.MethodPost, base+"/deactivate", f.coachToken, map[string]string{"reason": "trancou a matrícula"})
	if off.status != http.StatusOK || off.body["status"] != "inactive" {
		t.Fatalf("inativar: %d %+v", off.status, off.body)
	}
	if again := doJSONAuth(t, f.client, http.MethodPost, base+"/deactivate", f.coachToken, nil); again.status != http.StatusConflict || again.body["code"] != "already_inactive" {
		t.Fatalf("inativar de novo: %d %+v", again.status, again.body)
	}

	// Login e refresh bloqueados; some da lista padrão e aparece com o filtro.
	if resp := studentLogin(t, f, email, "SenhaAluno123!"); resp.status != http.StatusUnauthorized {
		t.Fatalf("login do inativo: esperava 401, obtive %d", resp.status)
	}
	if resp := doPost(t, f.client, f.url+"/v1/auth/refresh", map[string]any{"refresh_token": refresh, "tenant_id": tenantID}); resp.status != http.StatusUnauthorized {
		t.Fatalf("refresh do inativo: esperava 401, obtive %d", resp.status)
	}
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/students", f.coachToken)); len(names) != 0 {
		t.Fatalf("lista padrão não deveria ter o inativo: %v", names)
	}
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/students?status=inactive", f.coachToken)); len(names) != 1 || names[0] != "Ana Alves" {
		t.Fatalf("filtro inactive: %v", names)
	}
	// O coach ainda abre a ficha do inativo e o M2M devolve o status.
	if resp := doGetAuth(t, f.client, base, f.coachToken); resp.status != http.StatusOK || resp.body["status"] != "inactive" {
		t.Fatalf("ficha do inativo: %d %+v", resp.status, resp.body)
	}
	// M2M em lote: o inativo volta com o status; id desconhecido fica fora.
	unknown := uuid.NewString()
	batch := map[string]any{"students": []map[string]string{
		{"tenant_id": tenantID, "student_id": studentID},
		{"tenant_id": tenantID, "student_id": unknown},
	}}
	m2m := internalPost(t, f, "/internal/v1/students/statuses", batch, true)
	m2mItems, _ := m2m.body["items"].([]any)
	if m2m.status != http.StatusOK || len(m2mItems) != 1 {
		t.Fatalf("M2M em lote: %d %+v", m2m.status, m2m.body)
	}
	if it := m2mItems[0].(map[string]any); it["student_id"] != studentID || it["tenant_id"] != tenantID || it["status"] != "inactive" {
		t.Fatalf("M2M em lote: item inesperado %+v", it)
	}
	if resp := internalPost(t, f, "/internal/v1/students/statuses", batch, false); resp.status != http.StatusUnauthorized {
		t.Fatalf("M2M sem token: %d", resp.status)
	}
	if resp := internalPost(t, f, "/internal/v1/students/statuses", map[string]any{"students": []any{}}, true); resp.status != http.StatusBadRequest {
		t.Fatalf("M2M com lista vazia: esperava 400, obtive %d", resp.status)
	}

	// M2M individual (P7.2): nome, e-mail e status; desconhecido = 404.
	getM2M := func(id string, withToken bool) jsonResponse {
		req, _ := http.NewRequest(http.MethodGet, f.url+"/internal/v1/students/"+id+"?tenant_id="+tenantID, nil)
		if withToken {
			req.Header.Set("X-Internal-Token", testInternalToken)
		}
		resp, err := f.client.Do(req)
		if err != nil {
			t.Fatalf("GET M2M aluno: %v", err)
		}
		defer resp.Body.Close()
		body := map[string]any{}
		_ = json.NewDecoder(resp.Body).Decode(&body)
		return jsonResponse{status: resp.StatusCode, body: body}
	}
	if one := getM2M(studentID, true); one.status != http.StatusOK || one.body["name"] != "Ana Alves" || one.body["email"] != email || one.body["status"] != "inactive" {
		t.Fatalf("M2M individual: %d %+v", one.status, one.body)
	}
	if one := getM2M(unknown, true); one.status != http.StatusNotFound || one.body["code"] != "student_not_found" {
		t.Fatalf("M2M individual desconhecido: %d %+v", one.status, one.body)
	}
	if one := getM2M(studentID, false); one.status != http.StatusUnauthorized {
		t.Fatalf("M2M individual sem token: %d", one.status)
	}

	// Reativar devolve o acesso.
	on := doJSONAuth(t, f.client, http.MethodPost, base+"/reactivate", f.coachToken, nil)
	if on.status != http.StatusOK || on.body["status"] != "active" {
		t.Fatalf("reativar: %d %+v", on.status, on.body)
	}
	if again := doJSONAuth(t, f.client, http.MethodPost, base+"/reactivate", f.coachToken, nil); again.status != http.StatusConflict || again.body["code"] != "already_active" {
		t.Fatalf("reativar de novo: %d %+v", again.status, again.body)
	}
	if resp := studentLogin(t, f, email, "SenhaAluno123!"); resp.status != http.StatusOK {
		t.Fatalf("login após reativar: %d %+v", resp.status, resp.body)
	}

	// Histórico: as duas transições, da mais recente para a mais antiga.
	hist := doGetAuth(t, f.client, base+"/status-history", f.coachToken)
	items, _ := hist.body["items"].([]any)
	if hist.status != http.StatusOK || len(items) != 3 {
		t.Fatalf("histórico: %d %+v", hist.status, hist.body)
	}
	last, first, accepted := items[0].(map[string]any), items[1].(map[string]any), items[2].(map[string]any)
	if last["from"] != "inactive" || last["to"] != "active" || first["from"] != "active" || first["to"] != "inactive" ||
		first["reason"] != "trancou a matrícula" || first["changed_by_name"] != "Coach Responsável" {
		t.Fatalf("eventos do histórico: %+v", items)
	}
	// O aceite do convite também entra, com o próprio aluno como autor.
	if accepted["from"] != "invited" || accepted["to"] != "active" || accepted["changed_by"] != studentID {
		t.Fatalf("evento do aceite do convite: %+v", accepted)
	}
}

// TestStudentAccessScope: coach de outro aluno recebe 404 em toda rota da
// ficha; owner enxerga todos; aluno não entra na área do professor.
func TestStudentAccessScope(t *testing.T) {
	f := newUsersFixture(t)
	coachB, _ := inviteCoach(t, f, f.coachToken, "Coach B")
	studentEmail := inviteStudent(t, f, f.coachToken, "Aluno do Owner")
	studentID := studentIDByName(t, f, f.coachToken, "Aluno do Owner")
	base := f.url + "/v1/students/" + studentID

	for name, resp := range map[string]jsonResponse{
		"get":      doGetAuth(t, f.client, base, coachB),
		"patch":    doJSONAuth(t, f.client, http.MethodPatch, base, coachB, map[string]string{"name": "X"}),
		"off":      doJSONAuth(t, f.client, http.MethodPost, base+"/deactivate", coachB, nil),
		"on":       doJSONAuth(t, f.client, http.MethodPost, base+"/reactivate", coachB, nil),
		"history":  doGetAuth(t, f.client, base+"/status-history", coachB),
		"unknown":  doGetAuth(t, f.client, f.url+"/v1/students/01a1b424-0000-7000-8000-000000000000", f.coachToken),
		"not-uuid": doGetAuth(t, f.client, f.url+"/v1/students/abc", f.coachToken),
	} {
		if resp.status != http.StatusNotFound || resp.body["code"] != "student_not_found" {
			t.Fatalf("%s: esperava 404 student_not_found, obtive %d %+v", name, resp.status, resp.body)
		}
	}
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/students", coachB)); len(names) != 0 {
		t.Fatalf("lista do coach B deveria ser vazia: %v", names)
	}
	// Mesmo pedindo coach_id de outro: o coach só enxerga os dele.
	ownerID := ownerUserID(t, f)
	if names := userNames(t, doGetAuth(t, f.client, f.url+"/v1/students?coach_id="+ownerID, coachB)); len(names) != 0 {
		t.Fatalf("coach_id de outro não deveria vazar: %v", names)
	}
	if got := doGetAuth(t, f.client, f.url+"/v1/students?coach_id="+ownerID, f.coachToken); len(userNames(t, got)) != 1 {
		t.Fatalf("owner filtra por coach_id: %+v", got.body)
	}

	student := studentLogin(t, f, studentEmail, "SenhaAluno123!").body["access_token"].(string)
	if resp := doGetAuth(t, f.client, f.url+"/v1/students", student); resp.status != http.StatusForbidden {
		t.Fatalf("aluno na lista de alunos: esperava 403, obtive %d", resp.status)
	}

	// Tenant alheio: owner de outro tenant não vê o aluno.
	other := newTenantOn(t, f)
	if resp := doGetAuth(t, f.client, base, other.coachToken); resp.status != http.StatusNotFound {
		t.Fatalf("cross-tenant: esperava 404, obtive %d", resp.status)
	}
}

// TestStudentInvalidTransition: aluno que ainda não aceitou o convite não é
// inativado, e a ficha dele traz o convite pendente.
func TestStudentInvalidTransition(t *testing.T) {
	f := newUsersFixture(t)
	email := uniqueEmail("convidado")
	inv := doPostAuth(t, f.client, f.url+"/v1/invitations", f.coachToken, map[string]any{
		"email": email, "role": "student", "name": "Convidado",
	})
	if inv.status != http.StatusCreated {
		t.Fatalf("convidar: %d %+v", inv.status, inv.body)
	}
	studentID := studentIDByName(t, f, f.coachToken, "Convidado")
	base := f.url + "/v1/students/" + studentID

	got := doGetAuth(t, f.client, base, f.coachToken)
	pending, _ := got.body["pending_invitation"].(map[string]any)
	if got.body["status"] != "invited" || pending == nil || pending["id"] != inv.body["id"] || pending["expired"] != false {
		t.Fatalf("ficha do convidado: %+v", got.body)
	}
	if resp := doJSONAuth(t, f.client, http.MethodPost, base+"/deactivate", f.coachToken, nil); resp.status != http.StatusConflict || resp.body["code"] != "invalid_status_transition" {
		t.Fatalf("inativar convidado: %d %+v", resp.status, resp.body)
	}
}

// TestStudentProfileEdit: o professor edita nome/telefone/nascimento do
// aluno; o aluno edita o próprio telefone/nascimento em /v1/me.
func TestStudentProfileEdit(t *testing.T) {
	f := newUsersFixture(t)
	email := inviteStudent(t, f, f.coachToken, "Bruno Barros")
	studentID := studentIDByName(t, f, f.coachToken, "Bruno Barros")
	base := f.url + "/v1/students/" + studentID

	patched := doJSONAuth(t, f.client, http.MethodPatch, base, f.coachToken, map[string]string{
		"name": "Bruno B. Barros", "phone": "+55 (11) 91234-5678", "birth_date": "1990-05-17",
	})
	if patched.status != http.StatusOK || patched.body["name"] != "Bruno B. Barros" ||
		patched.body["phone"] != "+55 (11) 91234-5678" || patched.body["birth_date"] != "1990-05-17" {
		t.Fatalf("editar cadastro: %d %+v", patched.status, patched.body)
	}
	// Campo omitido mantém; vazio apaga.
	cleared := doJSONAuth(t, f.client, http.MethodPatch, base, f.coachToken, map[string]string{"phone": ""})
	if cleared.body["phone"] != nil || cleared.body["birth_date"] != "1990-05-17" || cleared.body["name"] != "Bruno B. Barros" {
		t.Fatalf("apagar telefone: %+v", cleared.body)
	}
	for field, payload := range map[string]map[string]string{
		"name":       {"name": "  "},
		"phone":      {"phone": "abc"},
		"birth_date": {"birth_date": "17/05/1990"},
	} {
		resp := doJSONAuth(t, f.client, http.MethodPatch, base, f.coachToken, payload)
		if resp.status != http.StatusUnprocessableEntity || resp.body["code"] != "validation_error" {
			t.Fatalf("%s inválido: %d %+v", field, resp.status, resp.body)
		}
	}
	future := fmt.Sprintf("%d-01-01", 2999)
	if resp := doJSONAuth(t, f.client, http.MethodPatch, base, f.coachToken, map[string]string{"birth_date": future}); resp.status != http.StatusUnprocessableEntity {
		t.Fatalf("nascimento no futuro: %d", resp.status)
	}

	// O aluno edita o próprio cadastro (mas não o nome).
	student := studentLogin(t, f, email, "SenhaAluno123!").body["access_token"].(string)
	me := doJSONAuth(t, f.client, http.MethodPatch, f.url+"/v1/me", student, map[string]string{"phone": "11 98888-7777", "birth_date": "1991-01-02"})
	if me.status != http.StatusOK || me.body["phone"] != "11 98888-7777" || me.body["birth_date"] != "1991-01-02" || me.body["name"] != "Bruno B. Barros" {
		t.Fatalf("PATCH /v1/me: %d %+v", me.status, me.body)
	}
	if resp := doJSONAuth(t, f.client, http.MethodPatch, f.url+"/v1/me", student, map[string]string{"name": "Hacker"}); resp.status != http.StatusUnprocessableEntity {
		t.Fatalf("aluno não muda o nome: %d", resp.status)
	}
	if got := doGetAuth(t, f.client, f.url+"/v1/me", student); got.status != http.StatusOK || got.body["phone"] != "11 98888-7777" {
		t.Fatalf("GET /v1/me: %d %+v", got.status, got.body)
	}
	if got := doGetAuth(t, f.client, base, f.coachToken); got.body["phone"] != "11 98888-7777" {
		t.Fatalf("o professor vê o telefone editado pelo aluno: %+v", got.body)
	}
}

// TestStudentListPaginatesPastPageSize: o cursor percorre a lista inteira,
// sem teto de itens (só de tamanho de página).
func TestStudentListPaginatesPastPageSize(t *testing.T) {
	f := newUsersFixture(t)
	for i := 0; i < 5; i++ {
		inviteStudent(t, f, f.coachToken, fmt.Sprintf("Aluno %02d", i))
	}
	var names []string
	cursor := ""
	for pages := 0; pages < 10; pages++ {
		url := f.url + "/v1/students?limit=2"
		if cursor != "" {
			url += "&cursor=" + cursor
		}
		resp := doGetAuth(t, f.client, url, f.coachToken)
		if resp.status != http.StatusOK {
			t.Fatalf("página %d: %d %+v", pages, resp.status, resp.body)
		}
		names = append(names, userNames(t, resp)...)
		next, _ := resp.body["next_cursor"].(string)
		if next == "" {
			break
		}
		cursor = next
	}
	if len(names) != 5 || names[0] != "Aluno 00" || names[4] != "Aluno 04" {
		t.Fatalf("paginação: %v", names)
	}
	if resp := doGetAuth(t, f.client, f.url+"/v1/students?q=Aluno%2003", f.coachToken); len(userNames(t, resp)) != 1 {
		t.Fatalf("busca: %+v", resp.body)
	}
	if resp := doGetAuth(t, f.client, f.url+"/v1/students?status=bogus", f.coachToken); resp.status != http.StatusBadRequest {
		t.Fatalf("status inválido: %d", resp.status)
	}
}
