package http

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// MountInternal registra as rotas M2M (ADR-013 §4) sob /internal/v1; o
// router as protege com RequireInternalToken. O identity as chama na exclusão
// de conta (ADR-017 §5, P7.5).
func (h *BillingHandler) MountInternal(r chi.Router) {
	r.Get("/users/{id}/pending", h.InternalPending)
	r.Delete("/users/{id}", h.InternalEraseUser)
}

func internalIDs(w http.ResponseWriter, r *http.Request) (userID, tenantID string, ok bool) {
	userID = chi.URLParam(r, "id")
	tenantID = r.URL.Query().Get("tenant_id")
	if _, err := uuid.Parse(userID); err != nil {
		writeError(w, errValidation("id"))
		return "", "", false
	}
	if _, err := uuid.Parse(tenantID); err != nil {
		writeError(w, errValidation("tenant_id"))
		return "", "", false
	}
	return userID, tenantID, true
}

// InternalPending — GET /internal/v1/users/{id}/pending?tenant_id=: se o
// aluno tem fatura em aberto (`open` ou `overdue`), com as contagens.
func (h *BillingHandler) InternalPending(w http.ResponseWriter, r *http.Request) {
	userID, tenantID, ok := internalIDs(w, r)
	if !ok {
		return
	}
	open, overdue, err := h.erasure.Pending(r.Context(), tenantID, userID)
	if err != nil {
		h.fail(w, "billing_pending_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"pending":          open+overdue > 0,
		"open_invoices":    open,
		"overdue_invoices": overdue,
	})
}

type eraseUserRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// InternalEraseUser — DELETE /internal/v1/users/{id}?tenant_id=, corpo
// {name, email}: cancela assinatura e faturas futuras e retém o titular
// como "conta excluída". Idempotente: repetir responde 204 sem efeito.
func (h *BillingHandler) InternalEraseUser(w http.ResponseWriter, r *http.Request) {
	userID, tenantID, ok := internalIDs(w, r)
	if !ok {
		return
	}
	var req eraseUserRequest
	if !decodeBody(w, r, &req) {
		return
	}
	req.Name, req.Email = strings.TrimSpace(req.Name), strings.TrimSpace(req.Email)
	if req.Name == "" {
		writeError(w, errValidation("name"))
		return
	}
	if req.Email == "" {
		writeError(w, errValidation("email"))
		return
	}
	today, _, ok := h.today(w, r.Context(), tenantID)
	if !ok {
		return
	}
	if err := h.erasure.EraseStudent(r.Context(), tenantID, userID, req.Name, req.Email, today); err != nil {
		h.fail(w, "billing_erase_failed", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
