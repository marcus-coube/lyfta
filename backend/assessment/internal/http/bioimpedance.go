package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// BioimpedanceHandler expõe as leituras de bioimpedância digitadas
// (ADR-012 §2, entrada manual) com o mesmo critério de permissão das medidas:
// aluno lança/lê/apaga as próprias, coach lança/lê/apaga as de qualquer aluno
// do tenant.
type BioimpedanceHandler struct {
	logger *slog.Logger
	repo   *repo.BioimpedanceRepo
}

// NewBioimpedanceHandler cria o handler de bioimpedância.
func NewBioimpedanceHandler(logger *slog.Logger, r *repo.BioimpedanceRepo) *BioimpedanceHandler {
	return &BioimpedanceHandler{logger: logger, repo: r}
}

type bioimpedanceRequest struct {
	MeasuredAt   string   `json:"measured_at"`
	BodyFatPct   *float64 `json:"body_fat_pct"`
	MuscleMassKg *float64 `json:"muscle_mass_kg"`
	VisceralFat  *float64 `json:"visceral_fat"`
	BodyWaterPct *float64 `json:"body_water_pct"`
	BoneMassKg   *float64 `json:"bone_mass_kg"`
	BMRKcal      *int     `json:"bmr_kcal"`
	Notes        string   `json:"notes"`
}

type bioimpedanceDTO struct {
	ID           string    `json:"id"`
	StudentID    string    `json:"student_id"`
	CreatedBy    string    `json:"created_by"`
	MeasuredAt   string    `json:"measured_at"`
	BodyFatPct   *float64  `json:"body_fat_pct"`
	MuscleMassKg *float64  `json:"muscle_mass_kg"`
	VisceralFat  *float64  `json:"visceral_fat"`
	BodyWaterPct *float64  `json:"body_water_pct"`
	BoneMassKg   *float64  `json:"bone_mass_kg"`
	BMRKcal      *int      `json:"bmr_kcal"`
	Notes        string    `json:"notes,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type bioimpedanceListResponse struct {
	Items      []bioimpedanceDTO `json:"items"`
	NextCursor string            `json:"next_cursor,omitempty"`
}

func (h *BioimpedanceHandler) CreateMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.create(w, r, claims.TenantID, claims.Subject)
}

func (h *BioimpedanceHandler) CreateForStudent(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	studentID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	h.create(w, r, tenantID, studentID)
}

func (h *BioimpedanceHandler) ListMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.list(w, r, claims.TenantID, claims.Subject)
}

func (h *BioimpedanceHandler) ListForStudent(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	studentID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	h.list(w, r, tenantID, studentID)
}

func (h *BioimpedanceHandler) DeleteMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.delete(w, r, claims.TenantID, claims.Subject)
}

func (h *BioimpedanceHandler) DeleteForStudent(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	studentID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	h.delete(w, r, tenantID, studentID)
}

func (h *BioimpedanceHandler) create(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	var req bioimpedanceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	b, apiErr := parseBioimpedance(req)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	b.TenantID = tenantID
	b.StudentID = studentID
	b.CreatedBy = actorID(r)

	created, err := h.repo.Create(r.Context(), b)
	if err != nil {
		h.logger.Error("bioimpedance_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusCreated, toBioimpedanceDTO(created))
}

func (h *BioimpedanceHandler) list(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	cursorAt, cursorID, limit, apiErr := parseListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	items, hasMore, err := h.repo.List(r.Context(), tenantID, studentID, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("bioimpedance_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := bioimpedanceListResponse{Items: make([]bioimpedanceDTO, 0, len(items))}
	for _, b := range items {
		resp.Items = append(resp.Items, toBioimpedanceDTO(b))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.MeasuredAt, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *BioimpedanceHandler) delete(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	id := chi.URLParam(r, "record_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("record_id"))
		return
	}
	err := h.repo.Delete(r.Context(), tenantID, studentID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("bioimpedance_record"))
		return
	}
	if err != nil {
		h.logger.Error("bioimpedance_delete_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// parseBioimpedance espelha os CHECKs da migration 0002.
func parseBioimpedance(req bioimpedanceRequest) (domain.BioimpedanceRecord, *APIError) {
	measuredAt, apiErr := parseRequiredDate(req.MeasuredAt, "measured_at")
	if apiErr != nil {
		return domain.BioimpedanceRecord{}, apiErr
	}
	notes := strings.TrimSpace(req.Notes)
	if len(notes) > maxNotesLen {
		return domain.BioimpedanceRecord{}, fail("notes")
	}

	if req.BodyFatPct != nil && (*req.BodyFatPct < 0 || *req.BodyFatPct > 100) {
		return domain.BioimpedanceRecord{}, fail("body_fat_pct")
	}
	if req.MuscleMassKg != nil && (*req.MuscleMassKg < 0 || *req.MuscleMassKg > 999.99) {
		return domain.BioimpedanceRecord{}, fail("muscle_mass_kg")
	}
	if req.VisceralFat != nil && (*req.VisceralFat < 0 || *req.VisceralFat > 999.9) {
		return domain.BioimpedanceRecord{}, fail("visceral_fat")
	}
	if req.BodyWaterPct != nil && (*req.BodyWaterPct < 0 || *req.BodyWaterPct > 100) {
		return domain.BioimpedanceRecord{}, fail("body_water_pct")
	}
	if req.BoneMassKg != nil && (*req.BoneMassKg < 0 || *req.BoneMassKg > 99.99) {
		return domain.BioimpedanceRecord{}, fail("bone_mass_kg")
	}
	if req.BMRKcal != nil && *req.BMRKcal < 0 {
		return domain.BioimpedanceRecord{}, fail("bmr_kcal")
	}

	return domain.BioimpedanceRecord{
		MeasuredAt: measuredAt, Notes: notes,
		BodyFatPct: req.BodyFatPct, MuscleMassKg: req.MuscleMassKg, VisceralFat: req.VisceralFat,
		BodyWaterPct: req.BodyWaterPct, BoneMassKg: req.BoneMassKg, BMRKcal: req.BMRKcal,
	}, nil
}

func toBioimpedanceDTO(b domain.BioimpedanceRecord) bioimpedanceDTO {
	return bioimpedanceDTO{
		ID: b.ID, StudentID: b.StudentID, CreatedBy: b.CreatedBy, MeasuredAt: b.MeasuredAt.Format(time.DateOnly),
		BodyFatPct: b.BodyFatPct, MuscleMassKg: b.MuscleMassKg, VisceralFat: b.VisceralFat,
		BodyWaterPct: b.BodyWaterPct, BoneMassKg: b.BoneMassKg, BMRKcal: b.BMRKcal,
		Notes: b.Notes, CreatedAt: b.CreatedAt,
	}
}
