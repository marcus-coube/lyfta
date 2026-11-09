package http_test

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// claimOf lê uma claim do payload do access token (sem verificar assinatura).
func claimOf(t *testing.T, token, name string) any {
	t.Helper()
	raw, err := base64.RawURLEncoding.DecodeString(strings.Split(token, ".")[1])
	if err != nil {
		t.Fatalf("decodificar token: %v", err)
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("payload do token: %v", err)
	}
	return payload[name]
}

// TestTenantSettings cobre P5.1: GET para todo papel, PUT só do owner, fuso
// inválido = 422 invalid_timezone e a claim tz no JWT.
func TestTenantSettings(t *testing.T) {
	f := newUsersFixture(t)

	if tz := claimOf(t, f.coachToken, "tz"); tz != "America/Sao_Paulo" {
		t.Fatalf("claim tz do signup = %v, esperava o fuso padrão", tz)
	}

	got := doGetAuth(t, f.client, f.url+"/v1/tenant", f.coachToken)
	if got.status != http.StatusOK || got.body["timezone"] != "America/Sao_Paulo" || got.body["coach_billing_access"] != "status_only" {
		t.Fatalf("GET /v1/tenant: %d %+v", got.status, got.body)
	}

	// Aluno lê, mas não escreve.
	student, _ := inviteStudentSession(t, f, map[string]bool{"health_data": true})
	studentToken := student["access_token"].(string)
	if resp := doGetAuth(t, f.client, f.url+"/v1/tenant", studentToken); resp.status != http.StatusOK {
		t.Fatalf("aluno deveria ler o tenant: %d %+v", resp.status, resp.body)
	}
	if resp := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/tenant", studentToken, map[string]any{"timezone": "Europe/Lisbon"}); resp.status != http.StatusForbidden {
		t.Fatalf("aluno não pode escrever: %d %+v", resp.status, resp.body)
	}

	// Fuso inválido.
	for _, bad := range []string{"Marte/Olympus", "", "Local"} {
		resp := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/tenant", f.coachToken, map[string]any{"timezone": bad})
		if resp.status != http.StatusUnprocessableEntity || resp.body["code"] != "invalid_timezone" {
			t.Fatalf("fuso %q: %d %+v", bad, resp.status, resp.body)
		}
	}
	if resp := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/tenant", f.coachToken, map[string]any{"coach_billing_access": "tudo"}); resp.status != http.StatusUnprocessableEntity {
		t.Fatalf("coach_billing_access inválido: %d %+v", resp.status, resp.body)
	}

	// Owner muda; campos omitidos ficam como estavam.
	put := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/tenant", f.coachToken, map[string]any{
		"timezone": "Europe/Lisbon", "coach_billing_access": "own_students",
	})
	if put.status != http.StatusOK || put.body["timezone"] != "Europe/Lisbon" || put.body["coach_billing_access"] != "own_students" || put.body["name"] != "Academia Teste" {
		t.Fatalf("PUT /v1/tenant: %d %+v", put.status, put.body)
	}

	// Novo login/refresh já carrega o fuso novo na claim (aqui via consentimento,
	// que reemite o token).
	reissued := doJSONAuth(t, f.client, http.MethodPut, f.url+"/v1/me/consents", studentToken, map[string]any{
		"terms_version": testTermsVersion, "consents": map[string]bool{"health_data": true},
	})
	if reissued.status != http.StatusOK {
		t.Fatalf("reemitir token: %d %+v", reissued.status, reissued.body)
	}
	if tz := claimOf(t, reissued.body["access_token"].(string), "tz"); tz != "Europe/Lisbon" {
		t.Fatalf("claim tz após mudança = %v", tz)
	}
}

// TestInternalTenants cobre o M2M da P5.1: lista com cursor e leitura por id.
func TestInternalTenants(t *testing.T) {
	f := newUsersFixture(t)
	tenantID := tenantIDOf(t, f)
	_ = newTenantOn(t, f) // garante pelo menos 2 tenants

	if resp := internalGet(t, f, "/internal/v1/tenants", false); resp.status != http.StatusUnauthorized {
		t.Fatalf("sem token: %d", resp.status)
	}

	one := internalGet(t, f, "/internal/v1/tenants/"+tenantID, true)
	if one.status != http.StatusOK || one.body["timezone"] != "America/Sao_Paulo" || one.body["coach_billing_access"] != "status_only" {
		t.Fatalf("GET tenant: %d %+v", one.status, one.body)
	}
	if resp := internalGet(t, f, "/internal/v1/tenants/00000000-0000-7000-8000-000000000000", true); resp.status != http.StatusNotFound {
		t.Fatalf("tenant inexistente: %d %+v", resp.status, resp.body)
	}

	// Pagina de 1 em 1 e confere que o nosso tenant aparece na varredura.
	seen, cursor := false, ""
	for page := 0; page < 10000; page++ {
		path := "/internal/v1/tenants?limit=1"
		if cursor != "" {
			path += "&after=" + cursor
		}
		resp := internalGet(t, f, path, true)
		if resp.status != http.StatusOK {
			t.Fatalf("lista de tenants: %d %+v", resp.status, resp.body)
		}
		items := resp.body["items"].([]any)
		if len(items) != 1 {
			t.Fatalf("página com %d itens, esperava 1", len(items))
		}
		if items[0].(map[string]any)["id"] == tenantID {
			seen = true
		}
		next, _ := resp.body["next_cursor"].(string)
		if next == "" {
			break
		}
		cursor = next
	}
	if !seen {
		t.Fatalf("tenant %s não apareceu na varredura", tenantID)
	}
}
