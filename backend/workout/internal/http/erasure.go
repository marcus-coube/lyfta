package http

import (
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// ErasureHandler expõe a exclusão M2M dos dados de um usuário (ADR-008 §2,
// P4.5), chamada pelo identity na exclusão de conta — protegida por
// RequireInternalToken, não por JWT.
type ErasureHandler struct {
	logger  *slog.Logger
	erasure *repo.ErasureRepo
}

// NewErasureHandler cria o handler.
func NewErasureHandler(logger *slog.Logger, erasure *repo.ErasureRepo) *ErasureHandler {
	return &ErasureHandler{logger: logger, erasure: erasure}
}

// EraseUser — DELETE /internal/v1/users/{id}?tenant_id=. Idempotente: repetir
// responde 204 sem efeito.
func (h *ErasureHandler) EraseUser(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	tenantID := r.URL.Query().Get("tenant_id")
	if _, err := uuid.Parse(userID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	if _, err := uuid.Parse(tenantID); err != nil {
		writeError(w, errValidation("tenant_id"))
		return
	}
	if err := h.erasure.EraseUser(r.Context(), tenantID, userID); err != nil {
		h.logger.Error("erase_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
