package http

import (
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/billing/internal/repo"
	"github.com/marcus-coube/lyfta/billing/internal/studentdir"
)

func subscriptionError(err error) (APIError, bool) {
	var stateErr *repo.StateError
	switch {
	case errors.As(err, &stateErr):
		return errInvalidSubscriptionState(stateErr.Status), true
	case errors.Is(err, repo.ErrPlanArchived):
		return errPlanArchived(), true
	case errors.Is(err, repo.ErrSubscriptionExists):
		return errSubscriptionExists(), true
	case isNotFound(err):
		return errNotFound("subscription"), true
	}
	return APIError{}, false
}

// loadSubscription carrega a assinatura e aplica o vínculo do coach: o
// aluno de outro coach responde 404 `student_not_found`.
func (h *BillingHandler) loadSubscription(w http.ResponseWriter, r *http.Request) (repo.Subscription, bool) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return repo.Subscription{}, false
	}
	sub, err := h.subs.Get(r.Context(), claims.TenantID, id)
	if isNotFound(err) {
		writeError(w, errNotFound("subscription"))
		return repo.Subscription{}, false
	}
	if err != nil {
		h.fail(w, "billing_subscription_get_failed", err)
		return repo.Subscription{}, false
	}
	if !h.linked(w, r, claims, sub.StudentID) {
		return repo.Subscription{}, false
	}
	return sub, true
}

// ListSubscriptions — GET /v1/billing/subscriptions?student_id=&status=
func (h *BillingHandler) ListSubscriptions(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	studentID := r.URL.Query().Get("student_id")
	if studentID != "" {
		if _, err := uuid.Parse(studentID); err != nil {
			writeError(w, errValidation("student_id"))
			return
		}
		if !h.linked(w, r, claims, studentID) {
			return
		}
	}
	status := r.URL.Query().Get("status")
	if status != "" && status != "active" && status != "paused" && status != "canceled" {
		writeError(w, errValidation("status"))
		return
	}
	ids, err := h.scope(r.Context(), claims)
	if err != nil {
		h.fail(w, "coach_link_check_failed", err)
		return
	}
	items, err := h.subs.List(r.Context(), claims.TenantID, ids, studentID, status)
	if err != nil {
		h.fail(w, "billing_subscriptions_list_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// GetSubscription — GET /v1/billing/subscriptions/{id}
func (h *BillingHandler) GetSubscription(w http.ResponseWriter, r *http.Request) {
	if sub, ok := h.loadSubscription(w, r); ok {
		writeJSON(w, http.StatusOK, sub)
	}
}

type createSubscriptionRequest struct {
	StudentID     string `json:"student_id"`
	BillingPlanID string `json:"billing_plan_id"`
	AmountCents   *int64 `json:"amount_cents"`
	DueDay        int    `json:"due_day"`
	StartsOn      string `json:"starts_on"`
}

// CreateSubscription — POST /v1/billing/subscriptions. Grava a cópia do
// titular (nome e e-mail do identity), a assinatura e, se `starts_on` cair no
// mês corrente do tenant, a fatura desse período.
func (h *BillingHandler) CreateSubscription(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	var req createSubscriptionRequest
	if !decodeBody(w, r, &req) {
		return
	}
	if _, err := uuid.Parse(req.StudentID); err != nil {
		writeError(w, errValidation("student_id"))
		return
	}
	if _, err := uuid.Parse(req.BillingPlanID); err != nil {
		writeError(w, errValidation("billing_plan_id"))
		return
	}
	if req.DueDay < 1 || req.DueDay > 28 {
		writeError(w, errValidation("due_day"))
		return
	}
	startsOn, err := time.Parse(time.DateOnly, req.StartsOn)
	if err != nil {
		writeError(w, errValidation("starts_on"))
		return
	}
	if req.AmountCents != nil && !validAmount(*req.AmountCents) {
		writeError(w, errValidation("amount_cents"))
		return
	}
	if !h.linked(w, r, claims, req.StudentID) {
		return
	}

	student, err := h.students.Get(r.Context(), claims.TenantID, req.StudentID)
	if errors.Is(err, studentdir.ErrNotFound) {
		writeError(w, errStudentNotFound())
		return
	}
	if err != nil {
		h.fail(w, "student_lookup_failed", err)
		return
	}
	today, _, ok := h.today(w, r.Context(), claims.TenantID)
	if !ok {
		return
	}

	sub, first, err := h.subs.Create(r.Context(), claims.TenantID, repo.CreateSubscriptionInput{
		StudentID: req.StudentID, StudentName: student.Name, StudentEmail: student.Email,
		BillingPlanID: req.BillingPlanID, AmountCents: req.AmountCents, DueDay: req.DueDay,
		StartsOn: startsOn, Today: today,
	})
	if err != nil {
		if apiErr, known := subscriptionError(err); known {
			if isNotFound(err) {
				apiErr = errNotFound("billing_plan")
			}
			writeError(w, apiErr)
			return
		}
		h.fail(w, "billing_subscription_create_failed", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"subscription": sub, "invoice": first})
}

type patchSubscriptionRequest struct {
	AmountCents *int64 `json:"amount_cents"`
	DueDay      *int   `json:"due_day"`
}

// PatchSubscription — PATCH /v1/billing/subscriptions/{id}: valor e
// vencimento valem a partir da próxima fatura.
func (h *BillingHandler) PatchSubscription(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	sub, ok := h.loadSubscription(w, r)
	if !ok {
		return
	}
	var req patchSubscriptionRequest
	if !decodeBody(w, r, &req) {
		return
	}
	if req.AmountCents == nil && req.DueDay == nil {
		writeError(w, errValidation("amount_cents"))
		return
	}
	if req.AmountCents != nil && !validAmount(*req.AmountCents) {
		writeError(w, errValidation("amount_cents"))
		return
	}
	if req.DueDay != nil && (*req.DueDay < 1 || *req.DueDay > 28) {
		writeError(w, errValidation("due_day"))
		return
	}
	updated, err := h.subs.Patch(r.Context(), claims.TenantID, sub.ID, req.AmountCents, req.DueDay)
	if err != nil {
		if apiErr, known := subscriptionError(err); known {
			writeError(w, apiErr)
			return
		}
		h.fail(w, "billing_subscription_patch_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// transition serve pause|resume|cancel. Cancelar cancela as faturas `open`
// futuras e nunca as vencidas.
func (h *BillingHandler) transition(action string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, _ := ClaimsFromContext(r.Context())
		sub, ok := h.loadSubscription(w, r)
		if !ok {
			return
		}
		today, _, ok := h.today(w, r.Context(), claims.TenantID)
		if !ok {
			return
		}
		updated, err := h.subs.Transition(r.Context(), claims.TenantID, sub.ID, action, today)
		if err != nil {
			if apiErr, known := subscriptionError(err); known {
				writeError(w, apiErr)
				return
			}
			h.fail(w, "billing_subscription_transition_failed", err)
			return
		}
		writeJSON(w, http.StatusOK, updated)
	}
}
