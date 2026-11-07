package http_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// doJSONAuth faz uma requisição com corpo JSON e Bearer opcional.
func doJSONAuth(t *testing.T, client *http.Client, method, url, token string, payload any) jsonResponse {
	t.Helper()
	var body []byte
	if payload != nil {
		var err error
		if body, err = json.Marshal(payload); err != nil {
			t.Fatalf("marshal: %v", err)
		}
	}
	req, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("montar request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	if out == nil {
		out = map[string]any{}
	}
	return jsonResponse{status: resp.StatusCode, body: out}
}

// inviteStudentSession cria e aceita um convite de aluno com as finalidades
// pedidas e devolve o corpo do aceite (tokens + consentimentos) e o e-mail.
func inviteStudentSession(t *testing.T, f usersFixture, consents map[string]bool) (map[string]any, string) {
	t.Helper()
	email := uniqueEmail("aluno")
	if resp := doPostAuth(t, f.client, f.url+"/v1/invitations", f.coachToken, map[string]any{
		"email": email, "role": "student", "name": "Aluna Consentida",
	}); resp.status != http.StatusCreated {
		t.Fatalf("criar convite: %d %+v", resp.status, resp.body)
	}
	msg, _ := f.mailer.lastTo(email)
	accept := doPost(t, f.client, f.url+"/v1/invitations/accept", map[string]any{
		"token": tokenFromMail(t, msg), "password": "SenhaAluno123!",
		"terms_version": testTermsVersion, "consents": consents,
	})
	if accept.status != http.StatusOK {
		t.Fatalf("aceitar convite: %d %+v", accept.status, accept.body)
	}
	return accept.body, email
}

func stringList(v any) []string {
	raw, _ := v.([]any)
	out := make([]string, 0, len(raw))
	for _, x := range raw {
		out = append(out, x.(string))
	}
	return out
}

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

// TestAcceptRequiresHealthDataForStudent: aluno novo não entra sem consentir
// health_data (Aceite do P4.5); com o consentimento, as claims carregam as
// finalidades concedidas.
func TestAcceptRequiresHealthDataForStudent(t *testing.T) {
	f := newUsersFixture(t)
	email := uniqueEmail("aluno")
	doPostAuth(t, f.client, f.url+"/v1/invitations", f.coachToken, map[string]any{"email": email, "role": "student"})
	msg, _ := f.mailer.lastTo(email)
	token := tokenFromMail(t, msg)

	cases := []struct {
		name     string
		payload  map[string]any
		wantCode string
		status   int
	}{
		{"sem versão dos termos", map[string]any{"token": token, "password": "SenhaAluno123!"}, "consent_required", http.StatusBadRequest},
		{"versão velha dos termos", map[string]any{"token": token, "password": "SenhaAluno123!", "terms_version": "velha"}, "terms_version_mismatch", http.StatusConflict},
		{"sem health_data", map[string]any{
			"token": token, "password": "SenhaAluno123!", "terms_version": testTermsVersion,
			"consents": map[string]bool{"health_data": false, "progress_photos": true},
		}, "consent_required", http.StatusBadRequest},
	}
	for _, tc := range cases {
		resp := doPost(t, f.client, f.url+"/v1/invitations/accept", tc.payload)
		if resp.status != tc.status || resp.body["code"] != tc.wantCode {
			t.Fatalf("%s: esperava %d %s, obtive %d %v", tc.name, tc.status, tc.wantCode, resp.status, resp.body)
		}
	}

	// Os acertos acima não consumiram o convite: com o consentimento entra.
	ok := doPost(t, f.client, f.url+"/v1/invitations/accept", map[string]any{
		"token": token, "password": "SenhaAluno123!", "terms_version": testTermsVersion,
		"consents": map[string]bool{"health_data": true, "progress_photos": false},
	})
	if ok.status != http.StatusOK {
		t.Fatalf("aceite com consentimento: %d %v", ok.status, ok.body)
	}
	granted := stringList(ok.body["consents"])
	if !contains(granted, "health_data") || !contains(granted, "terms") || contains(granted, "progress_photos") {
		t.Fatalf("finalidades vigentes erradas: %v", granted)
	}
	if ok.body["needs_consent"] != false {
		t.Fatalf("aluno consentido não deveria precisar consentir de novo: %v", ok.body)
	}
}

// TestConsentsRevokeAndGrantPhotos cobre GET/PUT /v1/me/consents: revogar
// fotos tira a finalidade das claims do token novo, e conceder de novo volta.
func TestConsentsRevokeAndGrantPhotos(t *testing.T) {
	f := newUsersFixture(t)
	session, _ := inviteStudentSession(t, f, map[string]bool{"health_data": true, "progress_photos": true})
	token := session["access_token"].(string)

	got := doGetAuth(t, f.client, f.url+"/v1/me/consents", token)
	if got.status != http.StatusOK || !contains(stringList(got.body["granted"]), "progress_photos") {
		t.Fatalf("GET consents: %d %v", got.status, got.body)
	}

	revoked := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/me/consents", token, map[string]any{
		"terms_version": testTermsVersion, "consents": map[string]bool{"progress_photos": false},
	})
	if revoked.status != http.StatusOK || contains(stringList(revoked.body["granted"]), "progress_photos") {
		t.Fatalf("revogar fotos: %d %v", revoked.status, revoked.body)
	}
	if revoked.body["needs_consent"] != false {
		t.Fatalf("revogar fotos não trava o app: %v", revoked.body)
	}
	if revoked.body["access_token"] == "" || revoked.body["access_token"] == nil {
		t.Fatalf("PUT deveria devolver um access_token com as claims novas: %v", revoked.body)
	}

	// Conceder de novo cria linha nova: o histórico é append-only.
	again := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/me/consents", token, map[string]any{
		"terms_version": testTermsVersion, "consents": map[string]bool{"progress_photos": true},
	})
	if !contains(stringList(again.body["granted"]), "progress_photos") {
		t.Fatalf("conceder de novo: %v", again.body)
	}

	bad := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/me/consents", token, map[string]any{
		"terms_version": testTermsVersion, "consents": map[string]bool{"gps": true},
	})
	if bad.status != http.StatusBadRequest {
		t.Fatalf("finalidade desconhecida: esperava 400, obtive %d", bad.status)
	}
}

// wipeConsents simula uma conta antiga, de antes do P4.5: apaga os registros
// de consentimento do usuário direto no banco.
func wipeConsents(t *testing.T, tenantID, userID string) {
	t.Helper()
	pool := testPool(t)
	err := repo.WithTenant(context.Background(), pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(context.Background(), `DELETE FROM consents WHERE user_id = $1`, userID)
		return err
	})
	if err != nil {
		t.Fatalf("apagar consentimentos: %v", err)
	}
}

// TestLegacyUserNeedsConsent: conta sem consentimento (usuário antigo) ainda
// loga, mas a resposta traz needs_consent — o gate do app — e o PUT libera.
func TestLegacyUserNeedsConsent(t *testing.T) {
	f := newUsersFixture(t)
	session, email := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	wipeConsents(t, session["tenant_id"].(string), session["user_id"].(string))

	login := doPost(t, f.client, f.url+"/v1/auth/login", map[string]any{"email": email, "password": "SenhaAluno123!"})
	if login.status != http.StatusOK || login.body["needs_consent"] != true {
		t.Fatalf("login de conta antiga: esperava needs_consent=true, obtive %d %v", login.status, login.body)
	}
	if len(stringList(login.body["consents"])) != 0 {
		t.Fatalf("conta antiga não tem finalidade vigente: %v", login.body["consents"])
	}

	put := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/me/consents", login.body["access_token"].(string), map[string]any{
		"terms_version": testTermsVersion, "consents": map[string]bool{"terms": true, "health_data": true},
	})
	if put.status != http.StatusOK || put.body["needs_consent"] != false {
		t.Fatalf("consentir pelo gate: %d %v", put.status, put.body)
	}
}

// TestTermsVersionBumpForcesConsent: versão nova dos termos derruba os
// consentimentos vigentes (as claims só levam os da versão atual).
func TestTermsVersionBumpForcesConsent(t *testing.T) {
	f := newUsersFixture(t)
	session, _ := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	token := session["access_token"].(string)

	// A versão velha ainda aparece como linha vigente, mas não conta.
	pool := testPool(t)
	err := repo.WithTenant(context.Background(), pool, session["tenant_id"].(string), func(tx pgx.Tx) error {
		_, err := tx.Exec(context.Background(), `UPDATE consents SET terms_version = 'antiga' WHERE user_id = $1`, session["user_id"])
		return err
	})
	if err != nil {
		t.Fatalf("envelhecer consentimentos: %v", err)
	}
	got := doGetAuth(t, f.client, f.url+"/v1/me/consents", token)
	if got.body["needs_consent"] != true {
		t.Fatalf("termo novo deveria exigir novo consentimento: %v", got.body)
	}
}

// TestDeleteAccountHappyPath: exclusão com a senha certa anonimiza o usuário,
// chama o eraser e o login do excluído falha (Aceite do P4.5).
func TestDeleteAccountHappyPath(t *testing.T) {
	server, _, mailer, eraser := newTestServerWithEraser(t)
	f := usersFixture{client: server.Client(), url: server.URL, mailer: mailer}
	f.coachToken = signupCoach(t, f)
	session, email := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	token := session["access_token"].(string)

	wrong := doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", token, map[string]string{"password": "senha-errada-1"})
	if wrong.status != http.StatusForbidden || wrong.body["code"] != "invalid_password" {
		t.Fatalf("senha errada: esperava 403 invalid_password, obtive %d %v", wrong.status, wrong.body)
	}
	if eraser.callCount() != 0 {
		t.Fatal("senha errada não pode disparar a exclusão nos serviços")
	}

	del := doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", token, map[string]string{"password": "SenhaAluno123!"})
	if del.status != http.StatusNoContent {
		t.Fatalf("excluir conta: esperava 204, obtive %d %v", del.status, del.body)
	}
	if eraser.callCount() != 1 {
		t.Fatalf("esperava 1 chamada de exclusão, obtive %d", eraser.callCount())
	}

	login := doPost(t, f.client, f.url+"/v1/auth/login", map[string]any{"email": email, "password": "SenhaAluno123!"})
	if login.status != http.StatusUnauthorized {
		t.Fatalf("login do excluído deveria falhar, obtive %d %v", login.status, login.body)
	}
	refresh := doPost(t, f.client, f.url+"/v1/auth/refresh", map[string]any{
		"refresh_token": session["refresh_token"], "tenant_id": session["tenant_id"],
	})
	if refresh.status != http.StatusUnauthorized {
		t.Fatalf("refresh do excluído deveria falhar, obtive %d", refresh.status)
	}

	// O usuário anonimizado some da lista do professor.
	list := doGetAuth(t, f.client, f.url+"/v1/users?role=student", f.coachToken)
	for _, name := range userNames(t, list) {
		if name == "Aluna Consentida" || name == "deleted" {
			t.Fatalf("usuário excluído ainda aparece na lista: %v", userNames(t, list))
		}
	}

	// O banco guarda o usuário anonimizado, sem e-mail nem hash.
	pool := testPool(t)
	var gotEmail, gotName, gotHash, status string
	err := repo.WithTenant(context.Background(), pool, session["tenant_id"].(string), func(tx pgx.Tx) error {
		return tx.QueryRow(context.Background(),
			`SELECT email, name, password_hash, status FROM users WHERE id = $1`, session["user_id"]).Scan(&gotEmail, &gotName, &gotHash, &status)
	})
	if err != nil {
		t.Fatalf("ler usuário: %v", err)
	}
	if status != "deleted" || gotEmail == email || gotName != "deleted" || gotHash != "" {
		t.Fatalf("usuário não foi anonimizado: email=%q name=%q hash=%q status=%q", gotEmail, gotName, gotHash, status)
	}
}

// TestDeleteAccountServiceDown: serviço fora do ar = 502 erasure_failed, o
// usuário segue `deleting` (sem login) e a repetição conclui.
func TestDeleteAccountServiceDown(t *testing.T) {
	server, _, mailer, eraser := newTestServerWithEraser(t)
	f := usersFixture{client: server.Client(), url: server.URL, mailer: mailer}
	f.coachToken = signupCoach(t, f)
	session, email := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	token := session["access_token"].(string)

	eraser.setFailing("assessment")
	first := doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", token, map[string]string{"password": "SenhaAluno123!"})
	if first.status != http.StatusBadGateway || first.body["code"] != "erasure_failed" {
		t.Fatalf("serviço fora: esperava 502 erasure_failed, obtive %d %v", first.status, first.body)
	}
	params, _ := first.body["params"].(map[string]any)
	if !contains(stringList(params["services"]), "assessment") {
		t.Fatalf("o 502 deveria nomear o serviço que falhou: %v", first.body)
	}

	// Enquanto isso o login já está bloqueado.
	login := doPost(t, f.client, f.url+"/v1/auth/login", map[string]any{"email": email, "password": "SenhaAluno123!"})
	if login.status != http.StatusUnauthorized {
		t.Fatalf("usuário deleting não pode logar, obtive %d", login.status)
	}

	// Repetir com o serviço de volta conclui — a senha ainda confere porque o
	// hash só some na anonimização.
	eraser.setFailing()
	second := doJSONAuth(t, f.client, http.MethodDelete, f.url+"/v1/me", token, map[string]string{"password": "SenhaAluno123!"})
	if second.status != http.StatusNoContent {
		t.Fatalf("repetição deveria concluir (204), obtive %d %v", second.status, second.body)
	}
}

// TestOwnerCannotDeleteAccount: o owner recebe erro explicativo; encerrar o
// tenant é outro fluxo.
func TestOwnerCannotDeleteAccount(t *testing.T) {
	server, _, _, eraser := newTestServerWithEraser(t)
	client := server.Client()
	ownerToken, _ := signupOwner(t, client, server.URL)

	resp := doJSONAuth(t, client, http.MethodDelete, server.URL+"/v1/me", ownerToken, map[string]string{"password": "senha12345"})
	if resp.status != http.StatusForbidden || resp.body["code"] != "owner_cannot_delete" {
		t.Fatalf("owner: esperava 403 owner_cannot_delete, obtive %d %v", resp.status, resp.body)
	}
	if eraser.callCount() != 0 {
		t.Fatal("owner não pode disparar exclusão")
	}
}

// TestSignupRequiresTerms: o signup do owner exige o aceite dos termos.
func TestSignupRequiresTerms(t *testing.T) {
	server, _, _ := newTestServer(t)
	resp := doPost(t, server.Client(), server.URL+"/v1/tenants", map[string]any{
		"business_name": "Sem Termos", "slug": uniqueSlug("sem-termos"), "name": "Dono",
		"email": uniqueEmail("dono"), "password": "senha12345",
	})
	if resp.status != http.StatusBadRequest || resp.body["code"] != "consent_required" {
		t.Fatalf("signup sem termos: esperava 400 consent_required, obtive %d %v", resp.status, resp.body)
	}
}

// TestInternalConsents cobre o endpoint M2M que o assessment usa para checar
// o consentimento de outra pessoa.
func TestInternalConsents(t *testing.T) {
	f := newUsersFixture(t)
	session, _ := inviteStudentSession(t, f, map[string]bool{"health_data": true, "progress_photos": true})
	target := f.url + "/internal/v1/users/" + session["user_id"].(string) + "/consents?tenant_id=" + session["tenant_id"].(string)

	req, _ := http.NewRequest(http.MethodGet, target, nil)
	resp, err := f.client.Do(req)
	if err != nil {
		t.Fatalf("GET interno: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("sem X-Internal-Token: esperava 401, obtive %d", resp.StatusCode)
	}

	req, _ = http.NewRequest(http.MethodGet, target, nil)
	req.Header.Set("X-Internal-Token", testInternalToken)
	resp, err = f.client.Do(req)
	if err != nil {
		t.Fatalf("GET interno: %v", err)
	}
	defer resp.Body.Close()
	var body struct {
		Purposes []string `json:"purposes"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if resp.StatusCode != http.StatusOK || !contains(body.Purposes, "progress_photos") {
		t.Fatalf("consentimentos internos: %d %v", resp.StatusCode, body)
	}
}
