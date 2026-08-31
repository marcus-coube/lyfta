package http_test

import (
	"encoding/json"
	"net/http"
	"net/url"
	"testing"
)

// doGetAuth faz um GET autenticado e devolve status + corpo.
func doGetAuth(t *testing.T, client *http.Client, target, token string) jsonResponse {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, target, nil)
	if err != nil {
		t.Fatalf("montar GET %s: %v", target, err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("GET %s: %v", target, err)
	}
	defer resp.Body.Close()

	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if body == nil {
		body = map[string]any{}
	}
	return jsonResponse{status: resp.StatusCode, body: body}
}

// userNames extrai os nomes da lista, na ordem devolvida.
func userNames(t *testing.T, resp jsonResponse) []string {
	t.Helper()
	items, ok := resp.body["items"].([]any)
	if !ok {
		t.Fatalf("resposta sem items: %+v", resp.body)
	}
	names := make([]string, 0, len(items))
	for _, raw := range items {
		item, ok := raw.(map[string]any)
		if !ok {
			t.Fatalf("item malformado: %+v", raw)
		}
		names = append(names, item["name"].(string))
	}
	return names
}

// usersFixture é um tenant com um coach logado — o ponto de partida da tela
// de alunos do professor.
type usersFixture struct {
	client     *http.Client
	url        string
	mailer     *captureMailer
	coachToken string
}

func newUsersFixture(t *testing.T) usersFixture {
	t.Helper()
	server, _, mailer := newTestServer(t)
	f := usersFixture{client: server.Client(), url: server.URL, mailer: mailer}
	f.coachToken = signupCoach(t, f)
	return f
}

// newTenantOn cria outro tenant no mesmo servidor — é como o teste confere o
// isolamento sem subir uma segunda instância.
func newTenantOn(t *testing.T, f usersFixture) usersFixture {
	t.Helper()
	other := usersFixture{client: f.client, url: f.url, mailer: f.mailer}
	other.coachToken = signupCoach(t, other)
	return other
}

func signupCoach(t *testing.T, f usersFixture) string {
	t.Helper()
	resp := doPost(t, f.client, f.url+"/v1/tenants", map[string]any{
		"business_name": "Academia Teste",
		"slug":          uniqueSlug("academia"),
		"name":          "Coach Responsável",
		"email":         uniqueEmail("coach"),
		"password":      "SenhaForte123!",
	})
	if resp.status != http.StatusCreated {
		t.Fatalf("signup do coach: %d %+v", resp.status, resp.body)
	}
	return resp.body["access_token"].(string)
}

// inviteStudent cria e aceita um convite de aluno, devolvendo o e-mail usado.
// O nome vai no convite: é assim que a lista do professor mostra gente em vez
// de e-mail.
func inviteStudent(t *testing.T, f usersFixture, coachToken, name string) string {
	t.Helper()
	email := uniqueEmail("aluno")
	resp := doPostAuth(t, f.client, f.url+"/v1/invitations", coachToken, map[string]any{
		"email": email, "role": "student", "name": name,
	})
	if resp.status != http.StatusCreated {
		t.Fatalf("criar convite: %d %+v", resp.status, resp.body)
	}
	msg, ok := f.mailer.lastTo(email)
	if !ok {
		t.Fatalf("convite para %s não foi enviado", email)
	}
	accept := doPost(t, f.client, f.url+"/v1/invitations/accept", map[string]any{
		"token": tokenFromMail(t, msg), "password": "SenhaAluno123!",
	})
	if accept.status != http.StatusOK && accept.status != http.StatusCreated {
		t.Fatalf("aceitar convite: %d %+v", accept.status, accept.body)
	}
	return email
}

// TestListUsersForCoach cobre o endpoint que a tela de alunos do P1.6 usa:
// filtro por papel, busca e isolamento entre tenants.
func TestListUsersForCoach(t *testing.T) {
	f := newUsersFixture(t)

	// Sem filtro, o coach que criou a conta aparece na lista.
	all := doGetAuth(t, f.client, f.url+"/v1/users", f.coachToken)
	if all.status != http.StatusOK {
		t.Fatalf("listar usuários: %d %+v", all.status, all.body)
	}
	if len(userNames(t, all)) < 1 {
		t.Fatalf("a lista deveria conter ao menos o próprio coach: %+v", all.body)
	}

	inviteStudent(t, f, f.coachToken, "Ana Alves")
	studentEmail := inviteStudent(t, f, f.coachToken, "Bruno Barros")

	// `role=student` traz só alunos, ordenados por nome.
	students := doGetAuth(t, f.client, f.url+"/v1/users?role=student", f.coachToken)
	names := userNames(t, students)
	if len(names) != 2 || names[0] != "Ana Alves" || names[1] != "Bruno Barros" {
		t.Fatalf("esperava os dois alunos em ordem de nome, veio %+v", names)
	}

	// Busca por nome (o professor digita para achar o aluno).
	found := doGetAuth(t, f.client, f.url+"/v1/users?role=student&q="+url.QueryEscape("bruno"), f.coachToken)
	if names := userNames(t, found); len(names) != 1 || names[0] != "Bruno Barros" {
		t.Fatalf("busca por nome falhou: %+v", names)
	}

	// Papel fora do vocabulário é erro de contrato, não lista vazia.
	bad := doGetAuth(t, f.client, f.url+"/v1/users?role=nutricionista", f.coachToken)
	if bad.status != http.StatusBadRequest || bad.body["code"] != "validation_error" {
		t.Fatalf("papel inválido deveria dar 400 validation_error: %d %+v", bad.status, bad.body)
	}

	// Outro tenant não enxerga os alunos deste (ADR-001).
	other := newTenantOn(t, f)
	foreign := doGetAuth(t, f.client, f.url+"/v1/users?role=student", other.coachToken)
	if names := userNames(t, foreign); len(names) != 0 {
		t.Fatalf("RLS deveria esconder os alunos do outro tenant, veio %+v", names)
	}

	// Aluno não lista a academia inteira: o endpoint é de owner|coach.
	studentLogin := doPost(t, f.client, f.url+"/v1/auth/login", map[string]any{
		"email": studentEmail, "password": "SenhaAluno123!",
	})
	if studentLogin.status != http.StatusOK {
		t.Fatalf("login do aluno: %d %+v", studentLogin.status, studentLogin.body)
	}
	denied := doGetAuth(t, f.client, f.url+"/v1/users", studentLogin.body["access_token"].(string))
	if denied.status != http.StatusForbidden {
		t.Fatalf("aluno deveria receber 403, veio %d %+v", denied.status, denied.body)
	}

	// Sem sessão, 401.
	anon := doGetAuth(t, f.client, f.url+"/v1/users", "")
	if anon.status != http.StatusUnauthorized {
		t.Fatalf("sem token deveria dar 401, veio %d", anon.status)
	}
}

// TestListUsersPaginates confere o cursor keyset da listagem.
func TestListUsersPaginates(t *testing.T) {
	f := newUsersFixture(t)
	for _, name := range []string{"Carla Cardoso", "Diego Dias", "Elisa Esteves"} {
		inviteStudent(t, f, f.coachToken, name)
	}

	first := doGetAuth(t, f.client, f.url+"/v1/users?role=student&limit=2", f.coachToken)
	names := userNames(t, first)
	if len(names) != 2 || names[0] != "Carla Cardoso" {
		t.Fatalf("primeira página veio errada: %+v", names)
	}
	cursor, ok := first.body["next_cursor"].(string)
	if !ok || cursor == "" {
		t.Fatalf("com mais páginas deveria vir next_cursor: %+v", first.body)
	}

	second := doGetAuth(t, f.client,
		f.url+"/v1/users?role=student&limit=2&cursor="+url.QueryEscape(cursor), f.coachToken)
	if names := userNames(t, second); len(names) != 1 || names[0] != "Elisa Esteves" {
		t.Fatalf("segunda página veio errada: %+v", names)
	}
	if _, hasMore := second.body["next_cursor"]; hasMore {
		t.Fatalf("última página não deveria trazer cursor: %+v", second.body)
	}

	// Cursor corrompido é erro de contrato, não lista vazia.
	bad := doGetAuth(t, f.client, f.url+"/v1/users?cursor=nao!e!cursor", f.coachToken)
	if bad.status != http.StatusBadRequest || bad.body["code"] != "invalid_cursor" {
		t.Fatalf("cursor inválido deveria dar 400 invalid_cursor: %d %+v", bad.status, bad.body)
	}
}
