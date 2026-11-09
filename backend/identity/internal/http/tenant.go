package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// TenantHandler expõe as configurações do tenant (P5.1): leitura para todo
// papel, escrita só do owner, e a leitura M2M dos outros serviços.
type TenantHandler struct {
	logger  *slog.Logger
	tenants *repo.TenantRepo
}

// NewTenantHandler cria o handler de configurações do tenant.
func NewTenantHandler(logger *slog.Logger, tenants *repo.TenantRepo) *TenantHandler {
	return &TenantHandler{logger: logger, tenants: tenants}
}

type tenantResponse struct {
	ID                 string `json:"id"`
	Name               string `json:"name"`
	Slug               string `json:"slug"`
	Locale             string `json:"locale"`
	Timezone           string `json:"timezone"`
	CoachBillingAccess string `json:"coach_billing_access"`
}

func toTenantResponse(t domain.Tenant) tenantResponse {
	return tenantResponse{
		ID: t.ID, Name: t.Name, Slug: t.Slug, Locale: t.Locale,
		Timezone: t.Timezone, CoachBillingAccess: t.CoachBillingAccess,
	}
}

// validTimezone aceita só nome IANA que o Go resolve. "" (que o Go lê como
// UTC) e "Local" (fuso do servidor) ficam de fora: o fuso do tenant é sempre
// explícito (ADR-007 §3).
func validTimezone(name string) bool {
	if name == "" || strings.EqualFold(name, "local") {
		return false
	}
	_, err := time.LoadLocation(name)
	return err == nil
}

// Get — GET /v1/tenant (qualquer papel autenticado).
func (h *TenantHandler) Get(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	t, err := h.tenants.FindByID(r.Context(), claims.TenantID)
	if err != nil {
		h.logger.Error("tenant_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, toTenantResponse(t))
}

type putTenantRequest struct {
	Name               *string `json:"name"`
	Timezone           *string `json:"timezone"`
	CoachBillingAccess *string `json:"coach_billing_access"`
}

// Put — PUT /v1/tenant (só owner, a rota barra o resto). Campo omitido
// mantém o valor atual. Fuso inválido = 422 `invalid_timezone`.
func (h *TenantHandler) Put(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req putTenantRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	current, err := h.tenants.FindByID(r.Context(), claims.TenantID)
	if err != nil {
		h.logger.Error("tenant_put_load_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			writeError(w, errUnprocessable("name"))
			return
		}
		current.Name = name
	}
	if req.Timezone != nil {
		if !validTimezone(*req.Timezone) {
			writeError(w, errInvalidTimezone())
			return
		}
		current.Timezone = *req.Timezone
	}
	if req.CoachBillingAccess != nil {
		if !domain.IsKnownCoachBillingAccess(*req.CoachBillingAccess) {
			writeError(w, errUnprocessable("coach_billing_access"))
			return
		}
		current.CoachBillingAccess = *req.CoachBillingAccess
	}
	updated, err := h.tenants.Update(r.Context(), current)
	if err != nil {
		h.logger.Error("tenant_put_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, toTenantResponse(updated))
}

type internalTenantItem struct {
	ID       string `json:"id"`
	Timezone string `json:"timezone"`
}

// InternalList — GET /internal/v1/tenants?after=&limit= (M2M): id + fuso de
// todos os tenants, em páginas por cursor (o id do último), para os jobs que
// varrem tenants.
func (h *TenantHandler) InternalList(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	after := strings.TrimSpace(q.Get("after"))
	if after != "" {
		if _, err := uuid.Parse(after); err != nil {
			writeError(w, errInvalidCursor())
			return
		}
	}
	limit := repo.MaxTenantPageSize
	if raw := strings.TrimSpace(q.Get("limit")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > repo.MaxTenantPageSize {
			writeError(w, errValidation("limit"))
			return
		}
		limit = n
	}
	// Pede um a mais para saber se há próxima página.
	rows, err := h.tenants.ListAfter(r.Context(), after, limit+1)
	if err != nil {
		h.logger.Error("internal_tenants_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := struct {
		Items      []internalTenantItem `json:"items"`
		NextCursor string               `json:"next_cursor,omitempty"`
	}{Items: []internalTenantItem{}}
	if len(rows) > limit {
		rows = rows[:limit]
		resp.NextCursor = rows[len(rows)-1].ID
	}
	for _, t := range rows {
		resp.Items = append(resp.Items, internalTenantItem{ID: t.ID, Timezone: t.Timezone})
	}
	writeJSON(w, http.StatusOK, resp)
}

// InternalGet — GET /internal/v1/tenants/{id} (M2M): fuso e acesso do coach
// ao financeiro. 404 `tenant_not_found`.
func (h *TenantHandler) InternalGet(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	t, err := h.tenants.FindByID(r.Context(), id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errTenantNotFound())
		return
	}
	if err != nil {
		h.logger.Error("internal_tenant_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"id": t.ID, "timezone": t.Timezone, "coach_billing_access": t.CoachBillingAccess,
	})
}
