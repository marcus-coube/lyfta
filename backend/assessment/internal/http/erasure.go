package http

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// ObjectEraser apaga do storage tudo que um aluno enviou (as fotos de
// evolução). Implementado por media.Presigner.
type ObjectEraser interface {
	DeleteStudentObjects(ctx context.Context, tenantID, studentID string) error
}

// ErasureHandler expõe a exclusão M2M dos dados de um aluno (ADR-008 §2,
// P4.5), chamada pelo identity na exclusão de conta — protegida por
// RequireInternalToken, não por JWT.
type ErasureHandler struct {
	logger  *slog.Logger
	erasure *repo.ErasureRepo
	objects ObjectEraser
}

// NewErasureHandler cria o handler.
func NewErasureHandler(logger *slog.Logger, erasure *repo.ErasureRepo, objects ObjectEraser) *ErasureHandler {
	return &ErasureHandler{logger: logger, erasure: erasure, objects: objects}
}

// EraseUser — DELETE /internal/v1/users/{id}?tenant_id=. Exclusão física das
// medidas, da bioimpedância e das fotos (linhas e objetos no storage).
// Idempotente. Os objetos saem primeiro: se o storage falhar a resposta é 500
// e nada do banco foi tocado, então a repetição refaz tudo; apagar o banco
// antes perderia a pista do que faltou apagar.
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
	if err := h.objects.DeleteStudentObjects(r.Context(), tenantID, userID); err != nil {
		h.logger.Error("erase_user_objects_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if err := h.erasure.EraseUser(r.Context(), tenantID, userID); err != nil {
		h.logger.Error("erase_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
