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

// writeJSON serializa qualquer payload de sucesso com o status informado.
func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

var (
	errUnauthenticated = func() APIError {
		return newAPIError(http.StatusUnauthorized, "unauthenticated")
	}
	errForbidden = func() APIError {
		return newAPIError(http.StatusForbidden, "forbidden")
	}
	errInvalidBody = func() APIError {
		return newAPIError(http.StatusBadRequest, "invalid_body")
	}
	errValidation = func(field string) APIError {
		return newAPIError(http.StatusBadRequest, "validation_error", "field", field)
	}
	errInvalidCursor = func() APIError {
		return newAPIError(http.StatusBadRequest, "invalid_cursor")
	}
	// Aluno que não é do coach (ou não existe, ou é de outro tenant): o
	// mesmo 404 para os três casos (ADR-016 §4).
	errStudentNotFound = func() APIError {
		return newAPIError(http.StatusNotFound, "student_not_found")
	}
	errNotFound = func(resource string) APIError {
		return newAPIError(http.StatusNotFound, "not_found", "resource", resource)
	}
	errUnsupportedMediaType = func(contentType string) APIError {
		return newAPIError(http.StatusUnsupportedMediaType, "unsupported_media_type", "content_type", contentType)
	}
	errFileTooLarge = func(maxBytes int64) APIError {
		return newAPIError(http.StatusRequestEntityTooLarge, "file_too_large", "max_bytes", maxBytes)
	}
	// A key do presign não bate com a pasta da conversa alvo — ver
	// media.ValidKeyForConversation.
	errInvalidMediaKey = func() APIError {
		return newAPIError(http.StatusUnprocessableEntity, "invalid_media_key")
	}
	errInternal = func() APIError {
		return newAPIError(http.StatusInternalServerError, "internal_error")
	}
)
