package http

import (
	"encoding/json"
	"net/http"
)

// APIError é o envelope de erro padrão da API (backend/README.md): `code`
// estável para tradução no cliente (ADR-011 §3) + `params` para interpolação.
type APIError struct {
	Status int            `json:"-"`
	Code   string         `json:"code"`
	Params map[string]any `json:"params"`
}

func (e APIError) Error() string { return e.Code }

// newAPIError constrói um APIError com params opcionais (chave/valor
// alternados).
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

var (
	errUnauthenticated = func() APIError {
		return newAPIError(http.StatusUnauthorized, "unauthenticated")
	}
	errForbidden = func() APIError {
		return newAPIError(http.StatusForbidden, "forbidden")
	}
)
