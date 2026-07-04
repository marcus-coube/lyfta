package http

import (
	"encoding/json"
	"net/http"
)

// APIError é o envelope de erro padrão da API (backend/README.md): `code`
// estável para tradução no cliente (ADR-011) + `params` para interpolação.
type APIError struct {
	Status int            `json:"-"`
	Code   string         `json:"code"`
	Params map[string]any `json:"params"`
}

func (e APIError) Error() string { return e.Code }

// newAPIError constrói um APIError com params opcionais (chave/valor
// alternados), evitando `map[string]any{...}` repetido nos handlers.
func newAPIError(status int, code string, kv ...any) APIError {
	params := map[string]any{}
	for i := 0; i+1 < len(kv); i += 2 {
		if k, ok := kv[i].(string); ok {
			params[k] = kv[i+1]
		}
	}
	return APIError{Status: status, Code: code, Params: params}
}

// writeError serializa o envelope de erro com o status HTTP correspondente.
func writeError(w http.ResponseWriter, err APIError) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(err.Status)
	_ = json.NewEncoder(w).Encode(err)
}

// writeJSON serializa qualquer payload de sucesso com o status informado.
func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

var (
	errInvalidBody = func() APIError {
		return newAPIError(http.StatusBadRequest, "invalid_body")
	}
	errValidation = func(field string) APIError {
		return newAPIError(http.StatusBadRequest, "validation_error", "field", field)
	}
	errInvalidCredentials = func() APIError {
		return newAPIError(http.StatusUnauthorized, "invalid_credentials")
	}
	errMultipleTenants = func(tenants []tenantOption) APIError {
		e := newAPIError(http.StatusConflict, "multiple_tenants")
		e.Params["tenants"] = tenants
		return e
	}
	errInvalidToken = func() APIError {
		return newAPIError(http.StatusUnauthorized, "invalid_token")
	}
	errSlugTaken = func() APIError {
		return newAPIError(http.StatusConflict, "slug_taken")
	}
	errEmailTaken = func() APIError {
		return newAPIError(http.StatusConflict, "email_taken")
	}
	errInternal = func() APIError {
		return newAPIError(http.StatusInternalServerError, "internal_error")
	}
)

// tenantOption é a opção devolvida em 409 multiple_tenants (ADR-002 §2c).
type tenantOption struct {
	TenantID   string `json:"tenant_id"`
	TenantName string `json:"tenant_name"`
}
