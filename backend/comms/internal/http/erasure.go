package http

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/duo/comms/internal/repo"
)

// ErasureHandler expõe a exclusão M2M dos dados de um usuário (ADR-008 §2,
// P4.5), chamada pelo identity na exclusão de conta — protegida por
// RequireInternalToken, não por JWT.
type ErasureHandler struct {
	logger  *slog.Logger
	erasure *repo.ErasureRepo
	objects StudentObjectEraser
}

// StudentObjectEraser apaga do storage a mídia de execução de um aluno
// (satisfeito por *media.Presigner).
type StudentObjectEraser interface {
	DeleteStudentObjects(ctx context.Context, tenantID, studentID string) error
}

// NewErasureHandler cria o handler. objects pode ser nil só nos testes que não
// exercitam o storage.
func NewErasureHandler(logger *slog.Logger, erasure *repo.ErasureRepo, objects StudentObjectEraser) *ErasureHandler {
	return &ErasureHandler{logger: logger, erasure: erasure, objects: objects}
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
	// Objetos primeiro (ADR-020 §5): se o storage falhar o identity repete a
	// chamada — idempotente — e as linhas ainda apontam para o que sobrou.
	if h.objects != nil {
		if err := h.objects.DeleteStudentObjects(r.Context(), tenantID, userID); err != nil {
			h.logger.Error("erase_user_objects_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
	}
	if err := h.erasure.EraseUser(r.Context(), tenantID, userID); err != nil {
		h.logger.Error("erase_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
