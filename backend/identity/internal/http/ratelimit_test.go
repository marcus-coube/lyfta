package http_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
)

func login(t *testing.T, client *http.Client, baseURL, email, password string) jsonResponse {
	t.Helper()
	return doPost(t, client, baseURL+"/v1/auth/login", map[string]any{"email": email, "password": password})
}

// --- Limite de tentativas (ADR-002 §2c) -------------------------------------

func TestLoginLockoutAfterFailures(t *testing.T) {
	server, _, _ := newTestServer(t)
	client := server.Client()
	_, email := signupOwner(t, client, server.URL)

	for i := 1; i <= 5; i++ {
		if resp := login(t, client, server.URL, email, "senhaerrada1"); resp.status != http.StatusUnauthorized {
			t.Fatalf("falha %d: esperava 401, obtive %d %v", i, resp.status, resp.body)
		}
	}

	// Bloqueado por 5 minutos — inclusive com a senha certa.
	b, _ := json.Marshal(map[string]any{"email": email, "password": "senha12345"})
	raw, err := client.Post(server.URL+"/v1/auth/login", "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	defer raw.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(raw.Body).Decode(&body)
	if raw.StatusCode != http.StatusTooManyRequests || body["code"] != "too_many_requests" {
		t.Fatalf("esperava 429 too_many_requests, obtive %d %v", raw.StatusCode, body)
	}
	if got := raw.Header.Get("Retry-After"); got != "300" {
		t.Fatalf("esperava Retry-After 300, obtive %q", got)
	}
	params, _ := body["params"].(map[string]any)
	if params["retry_after_seconds"] != float64(300) {
		t.Fatalf("esperava retry_after_seconds 300, obtive %v", params)
	}

	// O bloqueio é do e-mail: outro e-mail do mesmo IP segue entrando.
	_, other := signupOwner(t, client, server.URL)
	if resp := login(t, client, server.URL, other, "senha12345"); resp.status != http.StatusOK {
		t.Fatalf("outro e-mail: esperava 200, obtive %d %v", resp.status, resp.body)
	}
}

func TestLoginSuccessResetsEmailFailures(t *testing.T) {
	server, _, _ := newTestServer(t)
	client := server.Client()
	_, email := signupOwner(t, client, server.URL)

	for round := 0; round < 2; round++ {
		for i := 0; i < 4; i++ {
			login(t, client, server.URL, email, "senhaerrada1")
		}
		if resp := login(t, client, server.URL, email, "senha12345"); resp.status != http.StatusOK {
			t.Fatalf("rodada %d: login certo deveria passar, obtive %d %v", round, resp.status, resp.body)
		}
	}
}

func TestForgotPasswordLimitedPerEmail(t *testing.T) {
	server, _, mailer := newTestServer(t)
	client := server.Client()
	_, email := signupOwner(t, client, server.URL)

	for i := 1; i <= 3; i++ {
		resp := doPost(t, client, server.URL+"/v1/auth/forgot-password", map[string]any{"email": email})
		if resp.status != http.StatusOK {
			t.Fatalf("pedido %d: esperava 200, obtive %d", i, resp.status)
		}
	}
	sent := mailer.count()
	resp := doPost(t, client, server.URL+"/v1/auth/forgot-password", map[string]any{"email": email})
	if resp.status != http.StatusTooManyRequests {
		t.Fatalf("4º pedido: esperava 429, obtive %d %v", resp.status, resp.body)
	}
	if mailer.count() != sent {
		t.Fatal("pedido bloqueado não pode enviar e-mail")
	}
}

func TestResetPasswordLimitedPerIP(t *testing.T) {
	server, _, _ := newTestServer(t)
	client := server.Client()

	for i := 1; i <= 10; i++ {
		resp := doPost(t, client, server.URL+"/v1/auth/reset-password", map[string]any{
			"token": fmt.Sprintf("token-falso-%d", i), "password": "senhanova123",
		})
		if resp.status == http.StatusTooManyRequests {
			t.Fatalf("tentativa %d: bloqueou cedo demais", i)
		}
	}
	resp := doPost(t, client, server.URL+"/v1/auth/reset-password", map[string]any{
		"token": "token-falso-11", "password": "senhanova123",
	})
	if resp.status != http.StatusTooManyRequests {
		t.Fatalf("11ª tentativa: esperava 429, obtive %d %v", resp.status, resp.body)
	}
}

// --- Login não revela academias sem a senha certa ---------------------------

func TestLoginDoesNotLeakTenantsWithWrongPassword(t *testing.T) {
	server, _, _ := newTestServer(t)
	client := server.Client()

	email := uniqueEmail("leak")
	passwords := []string{"senhaacademiaA1", "senhaacademiaB1"}
	var tenantIDs []string
	for i, pw := range passwords {
		resp := doPost(t, client, server.URL+"/v1/tenants", map[string]any{
			"business_name": fmt.Sprintf("Academia Leak %d", i),
			"slug":          uniqueSlug("academia-leak"),
			"name":          "Dono Leak",
			"email":         email,
			"password":      pw,
			"terms_version": testTermsVersion,
		})
		if resp.status != http.StatusCreated {
			t.Fatalf("signup %d: %d %v", i, resp.status, resp.body)
		}
		tenantIDs = append(tenantIDs, resp.body["tenant_id"].(string))
	}

	// Senha errada: 401 genérico, nunca a lista de academias.
	if resp := login(t, client, server.URL, email, "qualquercoisa1"); resp.status != http.StatusUnauthorized || resp.body["code"] != "invalid_credentials" {
		t.Fatalf("senha errada: esperava 401 invalid_credentials, obtive %d %v", resp.status, resp.body)
	}

	// Senha de uma academia só: entra direto nela, sem 409.
	resp := login(t, client, server.URL, email, passwords[1])
	if resp.status != http.StatusOK || resp.body["tenant_id"] != tenantIDs[1] {
		t.Fatalf("senha da academia B: esperava 200 no tenant %s, obtive %d %v", tenantIDs[1], resp.status, resp.body)
	}

	// tenant_id com a senha de outra academia não entra.
	cross := doPost(t, client, server.URL+"/v1/auth/login", map[string]any{
		"email": email, "password": passwords[1], "tenant_id": tenantIDs[0],
	})
	if cross.status != http.StatusUnauthorized {
		t.Fatalf("senha de B no tenant A: esperava 401, obtive %d %v", cross.status, cross.body)
	}
}
