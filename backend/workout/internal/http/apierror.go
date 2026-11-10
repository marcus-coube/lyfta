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
	errInvalidBody = func() APIError {
		return newAPIError(http.StatusBadRequest, "invalid_body")
	}
	errValidation = func(field string) APIError {
		return newAPIError(http.StatusBadRequest, "validation_error", "field", field)
	}
	errUnsupportedMediaType = func(contentType string) APIError {
		return newAPIError(http.StatusUnsupportedMediaType, "unsupported_media_type", "content_type", contentType)
	}
	errFileTooLarge = func(maxBytes int64) APIError {
		return newAPIError(http.StatusRequestEntityTooLarge, "file_too_large", "max_bytes", maxBytes)
	}
	// Aluno que não é do coach (ou não existe, ou é de outro tenant): o
	// mesmo 404 para os três casos (ADR-016 §4).
	errStudentNotFound = func() APIError {
		return newAPIError(http.StatusNotFound, "student_not_found")
	}
	errNotFound = func(resource string) APIError {
		return newAPIError(http.StatusNotFound, "not_found", "resource", resource)
	}
	// A biblioteca global é somente leitura para o tenant (ADR-010 §3): o
	// cliente traduz este código em "clone para editar".
	errExerciseIsGlobal = func() APIError {
		return newAPIError(http.StatusForbidden, "exercise_is_global")
	}
	// Publicar congela a versão (ADR-004 §1): congelar plano vazio em algum
	// nível não serve para nada. `reason` diz qual nível ficou vazio.
	errPlanIncomplete = func(reason, dayID string) APIError {
		return newAPIError(http.StatusUnprocessableEntity, "plan_incomplete", "reason", reason, "day_id", dayID)
	}
	// Publicar duas vezes seguidas não gera versão nova: sem rascunho aberto,
	// não há o que congelar.
	errNoDraft = func() APIError {
		return newAPIError(http.StatusConflict, "no_draft_to_publish")
	}
	// A árvore aponta para exercício que este tenant não enxerga (id de outro
	// tenant ou inexistente).
	errUnknownExercise = func(exerciseID string) APIError {
		return newAPIError(http.StatusUnprocessableEntity, "unknown_exercise", "exercise_id", exerciseID)
	}
	// O lote de sync veio maior que o teto: o device tem de fatiar a fila.
	errBatchTooLarge = func(maxEvents int) APIError {
		return newAPIError(http.StatusBadRequest, "batch_too_large", "max_events", maxEvents)
	}
	// Override de rotação apontando para um dia que não é da versão ativa do
	// aluno (ADR-004 §3).
	errDayNotInPlan = func(dayID string) APIError {
		return newAPIError(http.StatusUnprocessableEntity, "day_not_in_plan", "day_id", dayID)
	}
	// Modelo de treino (ADR-018): só o autor ou o owner edita e arquiva.
	errTemplateNotOwned = func() APIError {
		return newAPIError(http.StatusForbidden, "template_not_owned")
	}
	// Modelo arquivado não é editado, publicado nem atribuído.
	errTemplateArchived = func() APIError {
		return newAPIError(http.StatusConflict, "template_archived")
	}
	// Atribuir exige versão publicada do modelo.
	errTemplateNotPublished = func() APIError {
		return newAPIError(http.StatusUnprocessableEntity, "template_not_published")
	}
	// Reaplicar: o plano não nasceu deste modelo / está arquivado.
	errPlanNotFromTemplate = func() APIError {
		return newAPIError(http.StatusUnprocessableEntity, "plan_not_from_template")
	}
	errPlanArchived = func() APIError {
		return newAPIError(http.StatusConflict, "plan_archived")
	}
	errInvalidCursor = func() APIError {
		return newAPIError(http.StatusBadRequest, "invalid_cursor")
	}
	errInternal = func() APIError {
		return newAPIError(http.StatusInternalServerError, "internal_error")
	}
	errUnauthenticated = func() APIError {
		return newAPIError(http.StatusUnauthorized, "unauthenticated")
	}
	errForbidden = func() APIError {
		return newAPIError(http.StatusForbidden, "forbidden")
	}
)
