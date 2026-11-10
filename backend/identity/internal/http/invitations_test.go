package http_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/marcus-coube/lyfta/identity/internal/mail"
)

// captureMailer implementa mail.Mailer guardando as mensagens enviadas, para
// os testes do fluxo de convite/reset extraírem o token do link sem depender
// de e-mail real (Aceite do P0.4: fluxo completo com logMailer/capture).
type captureMailer struct {
	mu   sync.Mutex
	sent []mail.Message
}

func (m *captureMailer) Send(_ context.Context, msg mail.Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sent = append(m.sent, msg)
	return nil
}

// lastTo devolve a última mensagem enviada para o endereço informado.
func (m *captureMailer) lastTo(to string) (mail.Message, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := len(m.sent) - 1; i >= 0; i-- {
		if m.sent[i].To == to {
			return m.sent[i], true
		}
	}
	return mail.Message{}, false
}

func (m *captureMailer) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sent)
}

var tokenRe = regexp.MustCompile(`token=([A-Za-z0-9_\-]+)`)

// tokenFromMail extrai o token do link presente no corpo do e-mail.
func tokenFromMail(t *testing.T, msg mail.Message) string {
	t.Helper()
	match := tokenRe.FindStringSubmatch(msg.HTML)
	if len(match) < 2 {
		t.Fatalf("não encontrei token no e-mail: %s", msg.HTML)
	}
	return match[1]
}

// doPostAuth faz um POST autenticado (Bearer) e devolve status + corpo.
func doPostAuth(t *testing.T, client *http.Client, url, token string, payload any) jsonResponse {
	t.Helper()
	b, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	if err != nil {
		t.Fatalf("montar request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	defer resp.Body.Close()

	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if body == nil {
		body = map[string]any{}
	}
	return jsonResponse{status: resp.StatusCode, body: body}
}

// signupOwner cria um tenant novo e devolve (accessToken, ownerEmail).
func signupOwner(t *testing.T, client *http.Client, baseURL string) (string, string) {
	t.Helper()
	email := uniqueEmail("owner")
	resp := doPost(t, client, baseURL+"/v1/tenants", map[string]any{
		"business_name": "Academia Convite",
		"slug":          uniqueSlug("academia-convite"),
		"name":          "Owner Convite",
		"email":         email,
		"password":      "senha12345",
		"terms_version": testTermsVersion,
	})
	if resp.status != http.StatusCreated {
		t.Fatalf("signup owner: esperava 201, obtive %d: %v", resp.status, resp.body)
	}
	token, _ := resp.body["access_token"].(string)
	if token == "" {
		t.Fatalf("signup owner: esperava access_token, obtive %v", resp.body)
	}
	return token, email
}

// --- Aceite: convite -> aceite (auto-login) -> login do convidado ----------

func TestInvitationFlow(t *testing.T) {
	server, _, mailer := newTestServer(t)
	client := server.Client()

	ownerToken, _ := signupOwner(t, client, server.URL)
	inviteeEmail := uniqueEmail("aluno")

	created := doPostAuth(t, client, server.URL+"/v1/invitations", ownerToken, map[string]any{
		"email": inviteeEmail,
		"role":  "student",
	})
	if created.status != http.StatusCreated {
		t.Fatalf("criar convite: esperava 201, obtive %d: %v", created.status, created.body)
	}

	msg, ok := mailer.lastTo(inviteeEmail)
	if !ok {
		t.Fatalf("esperava e-mail de convite para %s", inviteeEmail)
	}
	// Quem convida é a academia, não o produto (E2E da P4.4).
	if !strings.Contains(msg.HTML, "Academia Convite") {
		t.Fatalf("e-mail de convite deveria trazer o nome da academia: %s", msg.HTML)
	}
	token := tokenFromMail(t, msg)

	// Aceite define a senha e faz auto-login (retorna tokens).
	accepted := doPost(t, client, server.URL+"/v1/invitations/accept", map[string]any{
		"token":         token,
		"password":      "senhadoaluno1",
		"terms_version": testTermsVersion, "consents": map[string]bool{"health_data": true},
	})
	if accepted.status != http.StatusOK {
		t.Fatalf("aceitar convite: esperava 200, obtive %d: %v", accepted.status, accepted.body)
	}
	if accepted.body["access_token"] == "" || accepted.body["refresh_token"] == "" {
		t.Fatalf("aceitar convite: esperava tokens (auto-login), obtive %v", accepted.body)
	}

	// Agora o aluno consegue logar com a senha que definiu.
	login := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    inviteeEmail,
		"password": "senhadoaluno1",
	})
	if login.status != http.StatusOK {
		t.Fatalf("login do aluno: esperava 200, obtive %d: %v", login.status, login.body)
	}

	// Reuso do token de convite (já aceito) deve falhar.
	reuse := doPost(t, client, server.URL+"/v1/invitations/accept", map[string]any{
		"token":         token,
		"password":      "outrasenha123",
		"terms_version": testTermsVersion, "consents": map[string]bool{"health_data": true},
	})
	if reuse.status != http.StatusUnauthorized || reuse.body["code"] != "invalid_token" {
		t.Fatalf("reuso de convite: esperava 401 invalid_token, obtive %d %v", reuse.status, reuse.body)
	}
}

// --- Aceite: criar convite exige sessão de owner|coach ---------------------

func TestInvitationRequiresAuth(t *testing.T) {
	server, signer, _ := newTestServer(t)
	client := server.Client()

	// Sem Bearer -> 401 unauthenticated.
	noAuth := doPostAuth(t, client, server.URL+"/v1/invitations", "", map[string]any{
		"email": uniqueEmail("x"),
		"role":  "student",
	})
	if noAuth.status != http.StatusUnauthorized || noAuth.body["code"] != "unauthenticated" {
		t.Fatalf("sem auth: esperava 401 unauthenticated, obtive %d %v", noAuth.status, noAuth.body)
	}

	// Token válido, mas só com papel student -> 403 forbidden.
	studentToken, _, err := signer.Sign("00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002", []string{"student"}, "pt-BR", "America/Sao_Paulo", nil)
	if err != nil {
		t.Fatalf("assinar token de student: %v", err)
	}
	forbidden := doPostAuth(t, client, server.URL+"/v1/invitations", studentToken, map[string]any{
		"email": uniqueEmail("y"),
		"role":  "student",
	})
	if forbidden.status != http.StatusForbidden || forbidden.body["code"] != "forbidden" {
		t.Fatalf("papel student: esperava 403 forbidden, obtive %d %v", forbidden.status, forbidden.body)
	}
}

// --- Aceite: reenvio invalida o token anterior -----------------------------

func TestInvitationResendInvalidatesPrevious(t *testing.T) {
	server, _, mailer := newTestServer(t)
	client := server.Client()

	ownerToken, _ := signupOwner(t, client, server.URL)
	inviteeEmail := uniqueEmail("reenvio")

	created := doPostAuth(t, client, server.URL+"/v1/invitations", ownerToken, map[string]any{
		"email": inviteeEmail,
		"role":  "student",
	})
	if created.status != http.StatusCreated {
		t.Fatalf("criar convite: esperava 201, obtive %d: %v", created.status, created.body)
	}
	invID, _ := created.body["id"].(string)
	firstMsg, _ := mailer.lastTo(inviteeEmail)
	firstToken := tokenFromMail(t, firstMsg)

	resent := doPostAuth(t, client, server.URL+"/v1/invitations/"+invID+"/resend", ownerToken, map[string]any{})
	if resent.status != http.StatusCreated {
		t.Fatalf("reenviar convite: esperava 201, obtive %d: %v", resent.status, resent.body)
	}
	secondMsg, _ := mailer.lastTo(inviteeEmail)
	secondToken := tokenFromMail(t, secondMsg)
	if secondToken == firstToken {
		t.Fatalf("reenvio deveria gerar um token novo, diferente do anterior")
	}

	// Token antigo não vale mais.
	oldFails := doPost(t, client, server.URL+"/v1/invitations/accept", map[string]any{
		"token":         firstToken,
		"password":      "senhadoaluno1",
		"terms_version": testTermsVersion, "consents": map[string]bool{"health_data": true},
	})
	if oldFails.status != http.StatusUnauthorized || oldFails.body["code"] != "invalid_token" {
		t.Fatalf("token antigo pós-reenvio: esperava 401 invalid_token, obtive %d %v", oldFails.status, oldFails.body)
	}

	// Token novo funciona.
	newWorks := doPost(t, client, server.URL+"/v1/invitations/accept", map[string]any{
		"token":         secondToken,
		"password":      "senhadoaluno1",
		"terms_version": testTermsVersion, "consents": map[string]bool{"health_data": true},
	})
	if newWorks.status != http.StatusOK {
		t.Fatalf("token novo pós-reenvio: esperava 200, obtive %d: %v", newWorks.status, newWorks.body)
	}
}

// --- Aceite: forgot-password + reset-password ------------------------------

func TestForgotAndResetPassword(t *testing.T) {
	server, _, mailer := newTestServer(t)
	client := server.Client()

	_, ownerEmail := signupOwner(t, client, server.URL)

	// forgot-password para e-mail existente: 200 e dispara e-mail.
	forgot := doPost(t, client, server.URL+"/v1/auth/forgot-password", map[string]any{
		"email": ownerEmail,
	})
	if forgot.status != http.StatusOK {
		t.Fatalf("forgot-password: esperava 200, obtive %d: %v", forgot.status, forgot.body)
	}
	msg, ok := mailer.lastTo(ownerEmail)
	if !ok {
		t.Fatalf("esperava e-mail de reset para %s", ownerEmail)
	}
	token := tokenFromMail(t, msg)

	// reset-password troca a senha.
	reset := doPost(t, client, server.URL+"/v1/auth/reset-password", map[string]any{
		"token":    token,
		"password": "novasenha123",
	})
	if reset.status != http.StatusNoContent {
		t.Fatalf("reset-password: esperava 204, obtive %d: %v", reset.status, reset.body)
	}

	// Login com a senha nova funciona; com a antiga, não.
	loginNew := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    ownerEmail,
		"password": "novasenha123",
	})
	if loginNew.status != http.StatusOK {
		t.Fatalf("login com senha nova: esperava 200, obtive %d: %v", loginNew.status, loginNew.body)
	}
	loginOld := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email":    ownerEmail,
		"password": "senha12345",
	})
	if loginOld.status != http.StatusUnauthorized {
		t.Fatalf("login com senha antiga: esperava 401, obtive %d: %v", loginOld.status, loginOld.body)
	}

	// Reuso do token de reset (uso único) deve falhar.
	reuse := doPost(t, client, server.URL+"/v1/auth/reset-password", map[string]any{
		"token":    token,
		"password": "maisumasenha1",
	})
	if reuse.status != http.StatusUnauthorized || reuse.body["code"] != "invalid_token" {
		t.Fatalf("reuso de token de reset: esperava 401 invalid_token, obtive %d %v", reuse.status, reuse.body)
	}
}

// --- Aceite: forgot-password não vaza existência de e-mail -----------------

func TestForgotPasswordUnknownEmailIsSilent(t *testing.T) {
	server, _, mailer := newTestServer(t)
	client := server.Client()

	before := mailer.count()
	resp := doPost(t, client, server.URL+"/v1/auth/forgot-password", map[string]any{
		"email": uniqueEmail("nao-existe"),
	})
	if resp.status != http.StatusOK {
		t.Fatalf("forgot-password e-mail inexistente: esperava 200, obtive %d: %v", resp.status, resp.body)
	}
	if mailer.count() != before {
		t.Fatalf("forgot-password e-mail inexistente: não deveria enviar e-mail")
	}
}

// --- Reenvio exige o vínculo (ADR-016 §4) -----------------------------------

// TestInvitationResendRequiresLink: coach de outro aluno recebe 404
// student_not_found; o coach vinculado e o owner reenviam; convite de
// coach/owner é só do owner.
func TestInvitationResendRequiresLink(t *testing.T) {
	f := newUsersFixture(t) // f.coachToken: owner do tenant
	coachA, _ := inviteCoach(t, f, f.coachToken, "Coach A")
	coachB, _ := inviteCoach(t, f, f.coachToken, "Coach B")

	invite := func(token, role string) string {
		t.Helper()
		resp := doPostAuth(t, f.client, f.url+"/v1/invitations", token, map[string]any{
			"email": uniqueEmail("pend"), "role": role,
		})
		if resp.status != http.StatusCreated {
			t.Fatalf("convidar %s: %d %v", role, resp.status, resp.body)
		}
		return resp.body["id"].(string)
	}
	resend := func(token, id string) jsonResponse {
		return doPostAuth(t, f.client, f.url+"/v1/invitations/"+id+"/resend", token, map[string]any{})
	}

	studentOfA := invite(coachA, "student")
	if resp := resend(coachB, studentOfA); resp.status != http.StatusNotFound || resp.body["code"] != "student_not_found" {
		t.Fatalf("coach de outro aluno: esperava 404 student_not_found, obtive %d %v", resp.status, resp.body)
	}
	if resp := resend(coachA, studentOfA); resp.status != http.StatusCreated {
		t.Fatalf("coach vinculado: esperava 201, obtive %d %v", resp.status, resp.body)
	}
	// O reenvio invalida o convite antigo; o owner testa com outro convite.
	studentOfA2 := invite(coachA, "student")
	if resp := resend(f.coachToken, studentOfA2); resp.status != http.StatusCreated {
		t.Fatalf("owner: esperava 201, obtive %d %v", resp.status, resp.body)
	}

	coachInvite := invite(f.coachToken, "coach")
	if resp := resend(coachA, coachInvite); resp.status != http.StatusForbidden {
		t.Fatalf("coach reenviando convite de coach: esperava 403, obtive %d %v", resp.status, resp.body)
	}
	if resp := resend(f.coachToken, coachInvite); resp.status != http.StatusCreated {
		t.Fatalf("owner reenviando convite de coach: esperava 201, obtive %d %v", resp.status, resp.body)
	}

	// Tenant alheio: convite de outro tenant nem existe para o coach de lá.
	other := newTenantOn(t, f)
	if resp := resend(other.coachToken, studentOfA2); resp.status != http.StatusNotFound || resp.body["code"] != "invitation_not_found" {
		t.Fatalf("cross-tenant: esperava 404 invitation_not_found, obtive %d %v", resp.status, resp.body)
	}

	// Convite inexistente (ou id malformado) é 404, não invalid_token.
	for _, id := range []string{"01a1b424-0000-7000-8000-000000000000", "nao-e-uuid"} {
		if resp := resend(f.coachToken, id); resp.status != http.StatusNotFound || resp.body["code"] != "invitation_not_found" {
			t.Fatalf("convite %q inexistente: esperava 404 invitation_not_found, obtive %d %v", id, resp.status, resp.body)
		}
	}
}

// TestCoachInvitesOnlyStudents: o coach não convida equipe (escalada de
// privilégio); o owner convida coach e owner.
func TestCoachInvitesOnlyStudents(t *testing.T) {
	f := newUsersFixture(t) // f.coachToken: owner do tenant
	coach, _ := inviteCoach(t, f, f.coachToken, "Coach C")

	for _, role := range []string{"coach", "owner"} {
		resp := doPostAuth(t, f.client, f.url+"/v1/invitations", coach, map[string]any{
			"email": uniqueEmail("esc"), "role": role,
		})
		if resp.status != http.StatusForbidden || resp.body["code"] != "forbidden" {
			t.Fatalf("coach convidando %s: esperava 403 forbidden, obtive %d %v", role, resp.status, resp.body)
		}
		if resp := doPostAuth(t, f.client, f.url+"/v1/invitations", f.coachToken, map[string]any{
			"email": uniqueEmail("ok"), "role": role,
		}); resp.status != http.StatusCreated {
			t.Fatalf("owner convidando %s: esperava 201, obtive %d %v", role, resp.status, resp.body)
		}
	}
	if resp := doPostAuth(t, f.client, f.url+"/v1/invitations", coach, map[string]any{
		"email": uniqueEmail("aluno"), "role": "student",
	}); resp.status != http.StatusCreated {
		t.Fatalf("coach convidando aluno: esperava 201, obtive %d %v", resp.status, resp.body)
	}
}
