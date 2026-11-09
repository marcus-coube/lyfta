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

// PurposeHealthData é a finalidade de consentimento dos dados de saúde
// (ADR-008 §1) — mesmo valor emitido pelo identity.
const PurposeHealthData = "health_data"

const (
	maxGoalNotesLen   = 500
	maxMedicalNotes   = 2000
	maxCoachNotesLen  = 2000
	maxInjuryDescrLen = 500
)

// ProfileHandler expõe a anamnese (P5.3): objetivo, experiência, observações
// de saúde e lesões. O aluno lê/edita a própria (`/me/profile`) sem nunca ver
// `coach_notes`; o coach vinculado ou o owner usa `/students/{id}/profile`.
// Dado de saúde: as duas portas exigem a finalidade `health_data` (gate no
// roteador).
type ProfileHandler struct {
	logger   *slog.Logger
	profiles *repo.ProfileRepo
	injuries *repo.InjuryRepo
}

// NewProfileHandler cria o handler de anamnese.
func NewProfileHandler(logger *slog.Logger, profiles *repo.ProfileRepo, injuries *repo.InjuryRepo) *ProfileHandler {
	return &ProfileHandler{logger: logger, profiles: profiles, injuries: injuries}
}

// target resolve quem é o aluno e quem age (o gate de `health_data` fica no
// roteador: RequireMyHealthData / RequireStudentHealthData). Escreve a resposta de erro e devolve ok=false quando a requisição não deve
// seguir.
type profileTarget struct {
	tenantID, studentID, actorID string
	isCoach                      bool
}

func (h *ProfileHandler) target(w http.ResponseWriter, r *http.Request, coach bool) (profileTarget, bool) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return profileTarget{}, false
	}
	t := profileTarget{tenantID: claims.TenantID, studentID: claims.Subject, actorID: claims.Subject, isCoach: coach}
	if !coach {
		return t, true
	}
	t.studentID = chi.URLParam(r, "id")
	if _, err := uuid.Parse(t.studentID); err != nil {
		writeError(w, errValidation("id"))
		return profileTarget{}, false
	}
	return t, true
}

type profileDTO struct {
	StudentID          string     `json:"student_id"`
	Goal               *string    `json:"goal"`
	GoalNotes          string     `json:"goal_notes"`
	TrainingExperience *string    `json:"training_experience"`
	WeeklyTarget       *int       `json:"weekly_target"`
	MedicalNotes       string     `json:"medical_notes"`
	CoachNotes         *string    `json:"coach_notes,omitempty"` // só na porta do coach
	UpdatedAt          *time.Time `json:"updated_at"`
}

func toProfileDTO(p domain.StudentProfile, withCoachNotes bool) profileDTO {
	dto := profileDTO{
		StudentID: p.StudentID, Goal: p.Goal, GoalNotes: p.GoalNotes,
		TrainingExperience: p.TrainingExperience, WeeklyTarget: p.WeeklyTarget, MedicalNotes: p.MedicalNotes,
	}
	if !p.UpdatedAt.IsZero() {
		dto.UpdatedAt = &p.UpdatedAt
	}
	if withCoachNotes {
		notes := p.CoachNotes
		dto.CoachNotes = &notes
	}
	return dto
}

type profileRequest struct {
	Goal               *string `json:"goal"`
	GoalNotes          string  `json:"goal_notes"`
	TrainingExperience *string `json:"training_experience"`
	WeeklyTarget       *int    `json:"weekly_target"`
	MedicalNotes       string  `json:"medical_notes"`
	CoachNotes         string  `json:"coach_notes"` // ignorada na porta do aluno
}

// GetMine — GET /v1/me/profile.
func (h *ProfileHandler) GetMine(w http.ResponseWriter, r *http.Request) { h.get(w, r, false) }

// GetForStudent — GET /v1/students/{id}/profile.
func (h *ProfileHandler) GetForStudent(w http.ResponseWriter, r *http.Request) { h.get(w, r, true) }

// PutMine — PUT /v1/me/profile.
func (h *ProfileHandler) PutMine(w http.ResponseWriter, r *http.Request) { h.put(w, r, false) }

// PutForStudent — PUT /v1/students/{id}/profile.
func (h *ProfileHandler) PutForStudent(w http.ResponseWriter, r *http.Request) { h.put(w, r, true) }

func (h *ProfileHandler) get(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	p, err := h.profiles.Get(r.Context(), t.tenantID, t.studentID)
	if errors.Is(err, repo.ErrNotFound) {
		// Sem anamnese ainda: perfil vazio, não erro.
		p = domain.StudentProfile{StudentID: t.studentID}
	} else if err != nil {
		h.logger.Error("profile_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, toProfileDTO(p, coach))
}

// put substitui os campos que a porta pode escrever (o aluno não escreve
// coach_notes) e cria o perfil se for o primeiro.
func (h *ProfileHandler) put(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	var req profileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	p, apiErr := parseProfile(req)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	p.TenantID, p.StudentID, p.UpdatedBy = t.tenantID, t.studentID, t.actorID

	saved, err := h.profiles.Upsert(r.Context(), p, coach)
	if err != nil {
		h.logger.Error("profile_put_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, toProfileDTO(saved, coach))
}

func parseProfile(req profileRequest) (domain.StudentProfile, *APIError) {
	p := domain.StudentProfile{
		GoalNotes:    strings.TrimSpace(req.GoalNotes),
		MedicalNotes: strings.TrimSpace(req.MedicalNotes),
		CoachNotes:   strings.TrimSpace(req.CoachNotes),
	}
	if req.Goal != nil && *req.Goal != "" {
		if !domain.Contains(domain.Goals, *req.Goal) {
			return p, fail("goal")
		}
		p.Goal = req.Goal
	}
	if req.TrainingExperience != nil && *req.TrainingExperience != "" {
		if !domain.Contains(domain.Experiences, *req.TrainingExperience) {
			return p, fail("training_experience")
		}
		p.TrainingExperience = req.TrainingExperience
	}
	if req.WeeklyTarget != nil {
		if *req.WeeklyTarget < 1 || *req.WeeklyTarget > 7 {
			return p, fail("weekly_target")
		}
		p.WeeklyTarget = req.WeeklyTarget
	}
	switch {
	case len(p.GoalNotes) > maxGoalNotesLen:
		return p, fail("goal_notes")
	case len(p.MedicalNotes) > maxMedicalNotes:
		return p, fail("medical_notes")
	case len(p.CoachNotes) > maxCoachNotesLen:
		return p, fail("coach_notes")
	}
	return p, nil
}

// ---- lesões ----

type injuryDTO struct {
	ID          string    `json:"id"`
	StudentID   string    `json:"student_id"`
	BodyRegion  string    `json:"body_region"`
	Description string    `json:"description"`
	Since       *string   `json:"since"`
	ResolvedAt  *string   `json:"resolved_at"`
	Active      bool      `json:"active"`
	CreatedAt   time.Time `json:"created_at"`
}

func toInjuryDTO(in domain.StudentInjury) injuryDTO {
	dto := injuryDTO{
		ID: in.ID, StudentID: in.StudentID, BodyRegion: in.BodyRegion, Description: in.Description,
		Active: in.ResolvedAt == nil, CreatedAt: in.CreatedAt,
	}
	if in.Since != nil {
		s := in.Since.Format(time.DateOnly)
		dto.Since = &s
	}
	if in.ResolvedAt != nil {
		s := in.ResolvedAt.Format(time.DateOnly)
		dto.ResolvedAt = &s
	}
	return dto
}

type injuryRequest struct {
	BodyRegion  string  `json:"body_region"`
	Description string  `json:"description"`
	Since       *string `json:"since"`
	ResolvedAt  *string `json:"resolved_at"`
}

// parseOptionalDate lê uma data YYYY-MM-DD opcional (nil ou vazio = ausente).
func parseOptionalDate(raw *string, field string) (*time.Time, *APIError) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return nil, nil
	}
	at, err := time.Parse(time.DateOnly, strings.TrimSpace(*raw))
	if err != nil {
		return nil, fail(field)
	}
	return &at, nil
}

func validateInjury(in domain.StudentInjury) *APIError {
	switch {
	case !domain.Contains(domain.BodyRegions, in.BodyRegion):
		return fail("body_region")
	case in.Description == "" || len(in.Description) > maxInjuryDescrLen:
		return fail("description")
	case in.Since != nil && in.ResolvedAt != nil && in.ResolvedAt.Before(*in.Since):
		return fail("resolved_at")
	}
	return nil
}

type injuryListResponse struct {
	Items []injuryDTO `json:"items"`
}

// ListMine — GET /v1/me/injuries.
func (h *ProfileHandler) ListMine(w http.ResponseWriter, r *http.Request) {
	h.listInjuries(w, r, false)
}

// ListForStudent — GET /v1/students/{id}/injuries.
func (h *ProfileHandler) ListForStudent(w http.ResponseWriter, r *http.Request) {
	h.listInjuries(w, r, true)
}

// CreateInjuryMine — POST /v1/me/injuries.
func (h *ProfileHandler) CreateInjuryMine(w http.ResponseWriter, r *http.Request) {
	h.createInjury(w, r, false)
}

// CreateInjuryForStudent — POST /v1/students/{id}/injuries.
func (h *ProfileHandler) CreateInjuryForStudent(w http.ResponseWriter, r *http.Request) {
	h.createInjury(w, r, true)
}

// UpdateInjuryMine — PATCH /v1/me/injuries/{injury_id}.
func (h *ProfileHandler) UpdateInjuryMine(w http.ResponseWriter, r *http.Request) {
	h.updateInjury(w, r, false)
}

// UpdateInjuryForStudent — PATCH /v1/students/{id}/injuries/{injury_id}.
func (h *ProfileHandler) UpdateInjuryForStudent(w http.ResponseWriter, r *http.Request) {
	h.updateInjury(w, r, true)
}

// DeleteInjuryMine — DELETE /v1/me/injuries/{injury_id}.
func (h *ProfileHandler) DeleteInjuryMine(w http.ResponseWriter, r *http.Request) {
	h.deleteInjury(w, r, false)
}

// DeleteInjuryForStudent — DELETE /v1/students/{id}/injuries/{injury_id}.
func (h *ProfileHandler) DeleteInjuryForStudent(w http.ResponseWriter, r *http.Request) {
	h.deleteInjury(w, r, true)
}

// listInjuries aceita `?active=true` para devolver só as não resolvidas.
func (h *ProfileHandler) listInjuries(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	items, err := h.injuries.List(r.Context(), t.tenantID, t.studentID, r.URL.Query().Get("active") == "true")
	if err != nil {
		h.logger.Error("injury_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := injuryListResponse{Items: make([]injuryDTO, 0, len(items))}
	for _, in := range items {
		resp.Items = append(resp.Items, toInjuryDTO(in))
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *ProfileHandler) createInjury(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	var req injuryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	in := domain.StudentInjury{
		TenantID: t.tenantID, StudentID: t.studentID, CreatedBy: t.actorID,
		BodyRegion: req.BodyRegion, Description: strings.TrimSpace(req.Description),
	}
	var apiErr *APIError
	if in.Since, apiErr = parseOptionalDate(req.Since, "since"); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if in.ResolvedAt, apiErr = parseOptionalDate(req.ResolvedAt, "resolved_at"); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if apiErr = validateInjury(in); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	created, err := h.injuries.Create(r.Context(), in)
	if err != nil {
		h.logger.Error("injury_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusCreated, toInjuryDTO(created))
}

// updateInjury é PATCH parcial: só os campos presentes mudam. `since` e
// `resolved_at` aceitam null para limpar (reabrir uma lesão resolvida).
func (h *ProfileHandler) updateInjury(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	id := chi.URLParam(r, "injury_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("injury_id"))
		return
	}
	var raw map[string]json.RawMessage
	if err := json.NewDecoder(r.Body).Decode(&raw); err != nil || raw == nil {
		writeError(w, errInvalidBody())
		return
	}

	// Falha de campo dentro do mutate aborta a transação sem gravar.
	var fieldErr *APIError
	updated, err := h.injuries.Update(r.Context(), t.tenantID, t.studentID, id, func(in *domain.StudentInjury) error {
		if v, present := raw["body_region"]; present {
			var s string
			if json.Unmarshal(v, &s) != nil {
				fieldErr = fail("body_region")
				return fieldErr
			}
			in.BodyRegion = s
		}
		if v, present := raw["description"]; present {
			var s string
			if json.Unmarshal(v, &s) != nil {
				fieldErr = fail("description")
				return fieldErr
			}
			in.Description = strings.TrimSpace(s)
		}
		for _, f := range []struct {
			name string
			dst  **time.Time
		}{{"since", &in.Since}, {"resolved_at", &in.ResolvedAt}} {
			v, present := raw[f.name]
			if !present {
				continue
			}
			var s *string
			if json.Unmarshal(v, &s) != nil {
				fieldErr = fail(f.name)
				return fieldErr
			}
			at, apiErr := parseOptionalDate(s, f.name)
			if apiErr != nil {
				fieldErr = apiErr
				return fieldErr
			}
			*f.dst = at
		}
		if apiErr := validateInjury(*in); apiErr != nil {
			fieldErr = apiErr
			return fieldErr
		}
		return nil
	})
	if fieldErr != nil {
		writeError(w, *fieldErr)
		return
	}
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("injury"))
		return
	}
	if err != nil {
		h.logger.Error("injury_update_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, toInjuryDTO(updated))
}

func (h *ProfileHandler) deleteInjury(w http.ResponseWriter, r *http.Request, coach bool) {
	t, ok := h.target(w, r, coach)
	if !ok {
		return
	}
	id := chi.URLParam(r, "injury_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("injury_id"))
		return
	}
	err := h.injuries.Delete(r.Context(), t.tenantID, t.studentID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("injury"))
		return
	}
	if err != nil {
		h.logger.Error("injury_delete_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
