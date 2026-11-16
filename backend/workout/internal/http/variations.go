package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/duo/workout/internal/repo"
)

// Variações de série (ADR-019, P9.2): cadastro do tenant, lido e escrito por
// owner e coach (conteúdo do tenant, sem autor dono). Sem DELETE.

const (
	maxVariationNameLen = 40
	maxVariationDescLen = 1000
)

// VariationHandler atende /v1/variations.
type VariationHandler struct {
	logger     *slog.Logger
	variations *repo.VariationRepo
}

// NewVariationHandler cria o handler de variações.
func NewVariationHandler(logger *slog.Logger, variations *repo.VariationRepo) *VariationHandler {
	return &VariationHandler{logger: logger, variations: variations}
}

type variationRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

func (req variationRequest) validate() (name, description, field string) {
	name = strings.TrimSpace(req.Name)
	description = strings.TrimSpace(req.Description)
	if n := utf8.RuneCountInString(name); n == 0 || n > maxVariationNameLen {
		return "", "", "name"
	}
	if utf8.RuneCountInString(description) > maxVariationDescLen {
		return "", "", "description"
	}
	return name, description, ""
}

// List — GET /v1/variations?q=&status=active|archived|all (padrão active).
func (h *VariationHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	status := r.URL.Query().Get("status")
	switch status {
	case "":
		status = "active"
	case "active", "archived", "all":
	default:
		writeError(w, errValidation("status"))
		return
	}
	items, err := h.variations.List(r.Context(), claims.TenantID, strings.TrimSpace(r.URL.Query().Get("q")), status)
	if err != nil {
		h.logger.Error("variations_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// Create — POST /v1/variations.
func (h *VariationHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req variationRequest
	if !decodeVariationBody(w, r, &req) {
		return
	}
	name, desc, field := req.validate()
	if field != "" {
		writeError(w, errValidation(field))
		return
	}
	v, err := h.variations.Create(r.Context(), claims.TenantID, claims.Subject, name, desc)
	if h.failed(w, err, "variation_create_failed") {
		return
	}
	writeJSON(w, http.StatusCreated, v)
}

// Update — PUT /v1/variations/{id}.
func (h *VariationHandler) Update(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	id, ok := variationID(w, r)
	if !ok {
		return
	}
	var req variationRequest
	if !decodeVariationBody(w, r, &req) {
		return
	}
	name, desc, field := req.validate()
	if field != "" {
		writeError(w, errValidation(field))
		return
	}
	v, err := h.variations.Update(r.Context(), claims.TenantID, id, name, desc)
	if h.failed(w, err, "variation_update_failed") {
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// Archive — POST /v1/variations/{id}/archive (idempotente).
func (h *VariationHandler) Archive(w http.ResponseWriter, r *http.Request) { h.setArchived(w, r, true) }

// Unarchive — POST /v1/variations/{id}/unarchive (idempotente).
func (h *VariationHandler) Unarchive(w http.ResponseWriter, r *http.Request) {
	h.setArchived(w, r, false)
}

func (h *VariationHandler) setArchived(w http.ResponseWriter, r *http.Request, archived bool) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	id, ok := variationID(w, r)
	if !ok {
		return
	}
	v, err := h.variations.SetArchived(r.Context(), claims.TenantID, id, archived)
	if h.failed(w, err, "variation_archive_failed") {
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// failed traduz o erro do repo; true = resposta já escrita.
func (h *VariationHandler) failed(w http.ResponseWriter, err error, logKey string) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("variation"))
	case errors.Is(err, repo.ErrVariationNameTaken):
		writeError(w, errVariationNameTaken())
	default:
		h.logger.Error(logKey, slog.Any("error", err))
		writeError(w, errInternal())
	}
	return true
}

func variationID(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		// id malformado nunca existe: mesmo 404 de variação de outro tenant.
		writeError(w, errNotFound("variation"))
		return "", false
	}
	return id, true
}

func decodeVariationBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		writeError(w, errInvalidBody())
		return false
	}
	return true
}
