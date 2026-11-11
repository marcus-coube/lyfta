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

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// MeasurementHandler expõe as medidas corporais digitadas (P2.3): o aluno
// lança e lê as próprias (`/me/measurements`), o coach lança e lê as de
// qualquer aluno do tenant (`/students/{id}/measurements`) — mesmo critério
// de "qualquer professor do tenant" do P1.4/P2.1; o vínculo coach↔aluno
// continua sendo dívida do identity.
type MeasurementHandler struct {
	logger       *slog.Logger
	measurements *repo.MeasurementRepo
}

// NewMeasurementHandler cria o handler de medidas corporais.
func NewMeasurementHandler(logger *slog.Logger, measurements *repo.MeasurementRepo) *MeasurementHandler {
	return &MeasurementHandler{logger: logger, measurements: measurements}
}

type measurementRequest struct {
	MeasuredAt string   `json:"measured_at"`
	WeightKg   *float64 `json:"weight_kg"`
	HeightCm   *float64 `json:"height_cm"`
	NeckCm     *float64 `json:"neck_cm"`
	ShoulderCm *float64 `json:"shoulder_cm"`
	ChestCm    *float64 `json:"chest_cm"`
	WaistCm    *float64 `json:"waist_cm"`
	AbdomenCm  *float64 `json:"abdomen_cm"`
	HipCm      *float64 `json:"hip_cm"`
	ArmLCm     *float64 `json:"arm_l_cm"`
	ArmRCm     *float64 `json:"arm_r_cm"`
	ThighLCm   *float64 `json:"thigh_l_cm"`
	ThighRCm   *float64 `json:"thigh_r_cm"`
	CalfLCm    *float64 `json:"calf_l_cm"`
	CalfRCm    *float64 `json:"calf_r_cm"`
	Notes      string   `json:"notes"`
}

type measurementDTO struct {
	ID         string    `json:"id"`
	StudentID  string    `json:"student_id"`
	CreatedBy  string    `json:"created_by"`
	MeasuredAt string    `json:"measured_at"`
	WeightKg   *float64  `json:"weight_kg"`
	HeightCm   *float64  `json:"height_cm"`
	NeckCm     *float64  `json:"neck_cm"`
	ShoulderCm *float64  `json:"shoulder_cm"`
	ChestCm    *float64  `json:"chest_cm"`
	WaistCm    *float64  `json:"waist_cm"`
	AbdomenCm  *float64  `json:"abdomen_cm"`
	HipCm      *float64  `json:"hip_cm"`
	ArmLCm     *float64  `json:"arm_l_cm"`
	ArmRCm     *float64  `json:"arm_r_cm"`
	ThighLCm   *float64  `json:"thigh_l_cm"`
	ThighRCm   *float64  `json:"thigh_r_cm"`
	CalfLCm    *float64  `json:"calf_l_cm"`
	CalfRCm    *float64  `json:"calf_r_cm"`
	Notes      string    `json:"notes,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type measurementListResponse struct {
	Items      []measurementDTO `json:"items"`
	NextCursor string           `json:"next_cursor,omitempty"`
}

// CreateMine grava uma medida do próprio aluno.
func (h *MeasurementHandler) CreateMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.create(w, r, claims.TenantID, claims.Subject)
}

// CreateForStudent grava uma medida lançada pelo coach para um aluno do
// tenant (avaliação presencial).
func (h *MeasurementHandler) CreateForStudent(w http.ResponseWriter, r *http.Request) {
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

// ListMine lista as medidas do próprio aluno.
func (h *MeasurementHandler) ListMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.list(w, r, claims.TenantID, claims.Subject)
}

// ListForStudent lista as medidas de um aluno do tenant, para o coach.
func (h *MeasurementHandler) ListForStudent(w http.ResponseWriter, r *http.Request) {
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

// DeleteMine apaga uma medida do próprio aluno.
func (h *MeasurementHandler) DeleteMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.delete(w, r, claims.TenantID, claims.Subject)
}

// DeleteForStudent apaga uma medida de um aluno do tenant, para o coach.
func (h *MeasurementHandler) DeleteForStudent(w http.ResponseWriter, r *http.Request) {
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

func (h *MeasurementHandler) create(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	var req measurementRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	m, apiErr := parseMeasurement(req)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	m.TenantID = tenantID
	m.StudentID = studentID
	m.CreatedBy = actorID(r)

	created, err := h.measurements.Create(r.Context(), m)
	if err != nil {
		h.logger.Error("measurement_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusCreated, toMeasurementDTO(created))
}

func (h *MeasurementHandler) list(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	cursorAt, cursorID, limit, apiErr := parseListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	items, hasMore, err := h.measurements.List(r.Context(), tenantID, studentID, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("measurement_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := measurementListResponse{Items: make([]measurementDTO, 0, len(items))}
	for _, m := range items {
		resp.Items = append(resp.Items, toMeasurementDTO(m))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.MeasuredAt, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *MeasurementHandler) delete(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	id := chi.URLParam(r, "measurement_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("measurement_id"))
		return
	}
	err := h.measurements.Delete(r.Context(), tenantID, studentID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("measurement"))
		return
	}
	if err != nil {
		h.logger.Error("measurement_delete_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// parseMeasurement valida o corpo recebido. Os limites espelham os CHECKs e a
// precisão NUMERIC do schema (P2.2): validar aqui devolve `validation_error`
// traduzível em vez de 500 vindo de um overflow no banco.
func parseMeasurement(req measurementRequest) (domain.BodyMeasurement, *APIError) {
	measuredAt, apiErr := parseRequiredDate(req.MeasuredAt, "measured_at")
	if apiErr != nil {
		return domain.BodyMeasurement{}, apiErr
	}
	m := domain.BodyMeasurement{MeasuredAt: measuredAt, Notes: strings.TrimSpace(req.Notes)}
	if len(m.Notes) > maxNotesLen {
		return domain.BodyMeasurement{}, fail("notes")
	}

	fields := []struct {
		v     *float64
		field string
		max   float64
	}{
		{req.WeightKg, "weight_kg", 999.99},
		{req.HeightCm, "height_cm", 9999.9},
		{req.NeckCm, "neck_cm", 9999.9},
		{req.ShoulderCm, "shoulder_cm", 9999.9},
		{req.ChestCm, "chest_cm", 9999.9},
		{req.WaistCm, "waist_cm", 9999.9},
		{req.AbdomenCm, "abdomen_cm", 9999.9},
		{req.HipCm, "hip_cm", 9999.9},
		{req.ArmLCm, "arm_l_cm", 9999.9},
		{req.ArmRCm, "arm_r_cm", 9999.9},
		{req.ThighLCm, "thigh_l_cm", 9999.9},
		{req.ThighRCm, "thigh_r_cm", 9999.9},
		{req.CalfLCm, "calf_l_cm", 9999.9},
		{req.CalfRCm, "calf_r_cm", 9999.9},
	}
	// weight_kg e height_cm exigem > 0 (CHECK); os demais aceitam 0 (CHECK >= 0).
	if req.WeightKg != nil && *req.WeightKg <= 0 {
		return domain.BodyMeasurement{}, fail("weight_kg")
	}
	if req.HeightCm != nil && *req.HeightCm <= 0 {
		return domain.BodyMeasurement{}, fail("height_cm")
	}
	for _, f := range fields {
		if f.v != nil && (*f.v < 0 || *f.v > f.max) {
			return domain.BodyMeasurement{}, fail(f.field)
		}
	}

	m.WeightKg, m.HeightCm = req.WeightKg, req.HeightCm
	m.NeckCm, m.ShoulderCm, m.ChestCm, m.WaistCm = req.NeckCm, req.ShoulderCm, req.ChestCm, req.WaistCm
	m.AbdomenCm, m.HipCm = req.AbdomenCm, req.HipCm
	m.ArmLCm, m.ArmRCm, m.ThighLCm, m.ThighRCm = req.ArmLCm, req.ArmRCm, req.ThighLCm, req.ThighRCm
	m.CalfLCm, m.CalfRCm = req.CalfLCm, req.CalfRCm
	return m, nil
}

func toMeasurementDTO(m domain.BodyMeasurement) measurementDTO {
	return measurementDTO{
		ID: m.ID, StudentID: m.StudentID, CreatedBy: m.CreatedBy, MeasuredAt: m.MeasuredAt.Format(time.DateOnly),
		WeightKg: m.WeightKg, HeightCm: m.HeightCm, NeckCm: m.NeckCm, ShoulderCm: m.ShoulderCm,
		ChestCm: m.ChestCm, WaistCm: m.WaistCm, AbdomenCm: m.AbdomenCm, HipCm: m.HipCm,
		ArmLCm: m.ArmLCm, ArmRCm: m.ArmRCm, ThighLCm: m.ThighLCm, ThighRCm: m.ThighRCm,
		CalfLCm: m.CalfLCm, CalfRCm: m.CalfRCm, Notes: m.Notes, CreatedAt: m.CreatedAt,
	}
}

// maxNotesLen é o teto de observação livre — não é regra de negócio, é teto
// de payload (mesmo critério do builder do workout).
const maxNotesLen = 500

// parseRequiredDate valida uma data obrigatória no formato YYYY-MM-DD.
func parseRequiredDate(raw, field string) (time.Time, *APIError) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, fail(field)
	}
	at, err := time.Parse(time.DateOnly, raw)
	if err != nil {
		return time.Time{}, fail(field)
	}
	return at, nil
}

// parseListQuery lê `cursor` e `limit` das três listagens do serviço.
func parseListQuery(r *http.Request) (cursorAt *time.Time, cursorID string, limit int, apiErr *APIError) {
	q := r.URL.Query()
	if raw := q.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			return nil, "", 0, fail("limit")
		}
		limit = parsed
	}
	if raw := strings.TrimSpace(q.Get("cursor")); raw != "" {
		at, id, err := decodeCursor(raw)
		if err != nil {
			apiErr := errInvalidCursor()
			return nil, "", 0, &apiErr
		}
		cursorAt, cursorID = &at, id
	}
	return cursorAt, cursorID, limit, nil
}

func fail(field string) *APIError {
	apiErr := errValidation(field)
	return &apiErr
}
