package http

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/billing/internal/repo"
	"github.com/marcus-coube/lyfta/billing/internal/security"
	"github.com/marcus-coube/lyfta/billing/internal/studentdir"
	"github.com/marcus-coube/lyfta/billing/internal/tenantsettings"
)

// TenantSettings lê fuso e modo de acesso do coach (ADR-017 §3/§4).
type TenantSettings interface {
	Get(ctx context.Context, tenantID string) (tenantsettings.Settings, error)
}

// StudentDirectory lê nome e e-mail do aluno no identity.
type StudentDirectory interface {
	Get(ctx context.Context, tenantID, studentID string) (studentdir.Student, error)
}

// BillingHandler expõe a API do financeiro (P7.2): planos de mensalidade,
// assinaturas, faturas, baixa manual, estorno, status derivado e a leitura do
// aluno. A matriz de acesso (owner / coach `own_students` / coach
// `status_only`) é aplicada por middleware por grupo de rotas; o vínculo do
// coach com o aluno (ADR-016) é conferido por recurso.
type BillingHandler struct {
	logger   *slog.Logger
	plans    *repo.PlanRepo
	subs     *repo.SubscriptionRepo
	invoices *repo.InvoiceRepo
	settings TenantSettings
	students StudentDirectory
	linker   StudentLinker
	// Now é injetável para teste (fuso do tenant, `paid_at`, vencimento).
	now func() time.Time
}

// NewBillingHandler cria o handler. now == nil usa o relógio do sistema.
func NewBillingHandler(
	logger *slog.Logger,
	plans *repo.PlanRepo, subs *repo.SubscriptionRepo, invoices *repo.InvoiceRepo,
	settings TenantSettings, students StudentDirectory, linker StudentLinker,
	now func() time.Time,
) *BillingHandler {
	if now == nil {
		now = time.Now
	}
	return &BillingHandler{logger: logger, plans: plans, subs: subs, invoices: invoices,
		settings: settings, students: students, linker: linker, now: now}
}

// Mount registra as rotas sob /v1 (já autenticado) conforme a matriz do P7.2.
func (h *BillingHandler) Mount(r chi.Router) {
	operator := h.requireOperator
	owner := h.requireOwner

	r.Route("/billing", func(r chi.Router) {
		r.With(operator).Get("/plans", h.ListPlans)
		r.With(owner).Post("/plans", h.CreatePlan)
		r.With(owner).Put("/plans/{id}", h.UpdatePlan)
		r.With(owner).Post("/plans/{id}/archive", h.ArchivePlan)

		r.With(operator).Get("/subscriptions", h.ListSubscriptions)
		r.With(operator).Post("/subscriptions", h.CreateSubscription)
		r.With(operator).Get("/subscriptions/{id}", h.GetSubscription)
		r.With(operator).Patch("/subscriptions/{id}", h.PatchSubscription)
		r.With(operator).Post("/subscriptions/{id}/pause", h.transition(repo.ActionPause))
		r.With(operator).Post("/subscriptions/{id}/resume", h.transition(repo.ActionResume))
		r.With(operator).Post("/subscriptions/{id}/cancel", h.transition(repo.ActionCancel))

		r.With(operator).Get("/invoices", h.ListInvoices)
		r.With(operator).Get("/invoices/{id}", h.GetInvoice)
		r.With(operator).Post("/invoices/{id}/payments", h.RecordPayment)
		r.With(owner).Post("/invoices/{id}/cancel", h.CancelInvoice)
		r.With(owner).Post("/payments/{id}/reverse", h.ReversePayment)

		// Status derivado, sem valores: todo coach e o owner (em qualquer modo).
		r.With(h.requireStaff).Get("/students/status", h.StudentStatuses)
	})
	// Leitura do aluno: só as próprias faturas.
	r.Get("/me/invoices", h.MyInvoices)
}

// ---- Acesso ----

func hasRole(claims *security.Claims, role string) bool {
	for _, r := range claims.Roles {
		if r == role {
			return true
		}
	}
	return false
}

func (h *BillingHandler) fail(w http.ResponseWriter, event string, err error) {
	h.logger.Error(event, slog.Any("error", err))
	writeError(w, errInternal())
}

func (h *BillingHandler) settingsOf(w http.ResponseWriter, ctx context.Context, tenantID string) (tenantsettings.Settings, bool) {
	s, err := h.settings.Get(ctx, tenantID)
	if err != nil {
		h.fail(w, "tenant_settings_failed", err)
		return tenantsettings.Settings{}, false
	}
	return s, true
}

// requireOwner: rotas só do owner (planos, estorno, cancelar fatura).
func (h *BillingHandler) requireOwner(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, errUnauthenticated())
			return
		}
		if !hasRole(claims, "owner") {
			writeError(w, errBillingAccessDenied())
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requireStaff: owner ou qualquer coach.
func (h *BillingHandler) requireStaff(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, errUnauthenticated())
			return
		}
		if !hasRole(claims, "owner") && !hasRole(claims, "coach") {
			writeError(w, errBillingAccessDenied())
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requireOperator: owner sempre; coach só no modo `own_students` (lido do
// identity com cache de 30 s, ADR-017 §3). Aluno nunca.
func (h *BillingHandler) requireOperator(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, errUnauthenticated())
			return
		}
		if hasRole(claims, "owner") {
			next.ServeHTTP(w, r)
			return
		}
		if !hasRole(claims, "coach") {
			writeError(w, errBillingAccessDenied())
			return
		}
		s, ok := h.settingsOf(w, r.Context(), claims.TenantID)
		if !ok {
			return
		}
		if s.CoachBillingAccess != tenantsettings.AccessOwnStudents {
			writeError(w, errBillingAccessDenied())
			return
		}
		next.ServeHTTP(w, r)
	})
}

// scope devolve o conjunto de alunos que o ator enxerga: nil para o owner
// (todos), a lista (possivelmente vazia) para o coach.
func (h *BillingHandler) scope(ctx context.Context, claims *security.Claims) ([]string, error) {
	if hasRole(claims, "owner") {
		return nil, nil
	}
	set, err := h.linker.StudentsOf(ctx, claims.TenantID, claims.Subject)
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(set))
	for id := range set {
		ids = append(ids, id)
	}
	return ids, nil
}

func (h *BillingHandler) linked(w http.ResponseWriter, r *http.Request, claims *security.Claims, studentID string) bool {
	if apiErr := checkStudentLink(r.Context(), h.logger, h.linker, claims, studentID); apiErr != nil {
		writeError(w, *apiErr)
		return false
	}
	return true
}

// ---- Utilidades ----

const maxBodyBytes = 64 << 10

func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes))
	if err := dec.Decode(dst); err != nil {
		writeError(w, errInvalidBody())
		return false
	}
	return true
}

func pathID(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("id"))
		return "", false
	}
	return id, true
}

// today é a data corrente no fuso do tenant, como 00:00 UTC (só o
// calendário importa), mais o fuso para quem precisa do instante local.
func (h *BillingHandler) today(w http.ResponseWriter, ctx context.Context, tenantID string) (time.Time, *time.Location, bool) {
	s, ok := h.settingsOf(w, ctx, tenantID)
	if !ok {
		return time.Time{}, nil, false
	}
	loc := s.Location()
	n := h.now().In(loc)
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC), loc, true
}

var (
	periodRe = regexp.MustCompile(`^[0-9]{4}-(0[1-9]|1[0-2])$`)
	statusRe = regexp.MustCompile(`^(open|paid|overdue|canceled)$`)
)

const (
	maxNameLen = 120
	maxNoteLen = 500
	// Teto sanitário do valor: R$ 10 milhões em centavos.
	maxAmountCents = 1_000_000_000
)

func validAmount(c int64) bool { return c > 0 && c <= maxAmountCents }

func isNotFound(err error) bool { return errors.Is(err, repo.ErrNotFound) }

func trimmed(s string) string { return strings.TrimSpace(s) }
