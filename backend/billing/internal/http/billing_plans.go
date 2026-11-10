package http

import (
	"net/http"
)

type planRequest struct {
	Name        string `json:"name"`
	AmountCents int64  `json:"amount_cents"`
}

func (req planRequest) validate() (name string, field string) {
	name = trimmed(req.Name)
	if name == "" || len([]rune(name)) > maxNameLen {
		return "", "name"
	}
	if !validAmount(req.AmountCents) {
		return "", "amount_cents"
	}
	return name, ""
}

// ListPlans — GET /v1/billing/plans[?active=true]: owner e coach
// `own_students` (leitura, para assinar).
func (h *BillingHandler) ListPlans(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	items, err := h.plans.List(r.Context(), claims.TenantID, r.URL.Query().Get("active") == "true")
	if err != nil {
		h.fail(w, "billing_plans_list_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// CreatePlan — POST /v1/billing/plans (owner).
func (h *BillingHandler) CreatePlan(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	var req planRequest
	if !decodeBody(w, r, &req) {
		return
	}
	name, field := req.validate()
	if field != "" {
		writeError(w, errValidation(field))
		return
	}
	p, err := h.plans.Create(r.Context(), claims.TenantID, name, req.AmountCents)
	if err != nil {
		h.fail(w, "billing_plan_create_failed", err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

// UpdatePlan — PUT /v1/billing/plans/{id} (owner). As assinaturas existentes
// mantêm o valor que copiaram ao assinar.
func (h *BillingHandler) UpdatePlan(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req planRequest
	if !decodeBody(w, r, &req) {
		return
	}
	name, field := req.validate()
	if field != "" {
		writeError(w, errValidation(field))
		return
	}
	p, err := h.plans.Update(r.Context(), claims.TenantID, id, name, req.AmountCents)
	if isNotFound(err) {
		writeError(w, errNotFound("billing_plan"))
		return
	}
	if err != nil {
		h.fail(w, "billing_plan_update_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

// ArchivePlan — POST /v1/billing/plans/{id}/archive (owner, idempotente).
func (h *BillingHandler) ArchivePlan(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	p, err := h.plans.Archive(r.Context(), claims.TenantID, id)
	if isNotFound(err) {
		writeError(w, errNotFound("billing_plan"))
		return
	}
	if err != nil {
		h.fail(w, "billing_plan_archive_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}
