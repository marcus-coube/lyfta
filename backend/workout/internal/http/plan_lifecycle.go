package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
	"github.com/marcus-coube/lyfta/workout/internal/security"
)

// Ciclo de vida dos planos do aluno (P6.2): duplicar, arquivar, ativar,
// histórico de versões e override do próximo dia pelo coach.

type duplicateRequest struct {
	// StudentID vazio = o mesmo aluno do plano de origem.
	StudentID string `json:"student_id"`
}

type versionSummaryDTO struct {
	versionRefDTO
	PublishedBy    string `json:"published_by,omitempty"`
	DaysCount      int    `json:"days_count"`
	ExercisesCount int    `json:"exercises_count"`
}

type rotationDTO struct {
	PlanID          string `json:"plan_id"`
	ActiveVersionID string `json:"active_version_id"`
	NextDayID       string `json:"next_day_id,omitempty"`
	NextDayLabel    string `json:"next_day_label,omitempty"`
}

type nextDayRequest struct {
	DayID string `json:"day_id"`
}

// loadStudentPlan carrega um plano de aluno e checa o acesso de escrita; modelo
// responde 404 (tem rotas próprias em /templates).
func (h *PlanHandler) loadStudentPlan(r *http.Request, claims *security.Claims) (domain.Plan, *APIError) {
	plan, apiErr := h.loadPlan(r.Context(), claims.TenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		return domain.Plan{}, apiErr
	}
	if plan.Kind != domain.PlanKindAssigned {
		e := errNotFound("plan")
		return domain.Plan{}, &e
	}
	if apiErr := h.authorizePlan(r.Context(), claims, plan, true); apiErr != nil {
		return domain.Plan{}, apiErr
	}
	return plan, nil
}

// Duplicate responde POST /v1/plans/{id}/duplicate: copia a versão mais
// recente para um plano novo em rascunho, do mesmo aluno ou de outro do
// vínculo do ator. O autor da cópia é o professor vinculado ao aluno de
// destino, como em qualquer plano novo.
func (h *PlanHandler) Duplicate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req duplicateRequest
	if r.ContentLength != 0 {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, errInvalidBody())
			return
		}
	}

	src, apiErr := h.loadPlan(r.Context(), claims.TenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if src.Kind != domain.PlanKindAssigned {
		writeError(w, errNotFound("plan"))
		return
	}
	// Ler a origem exige o vínculo com o aluno dela.
	if apiErr := h.authorizePlan(r.Context(), claims, src, false); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	studentID := strings.TrimSpace(req.StudentID)
	if studentID == "" {
		studentID = src.StudentID
	} else if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("student_id"))
		return
	}
	// O destino passa pelas mesmas regras de um plano novo: vínculo,
	// existência no identity e autor = professor vinculado.
	if apiErr := h.checkStudent(r.Context(), claims, studentID); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	existing, err := h.existingStudents(r.Context(), claims.TenantID, []string{studentID})
	if err != nil {
		h.logger.Error("student_lookup_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if _, ok := existing[studentID]; !ok {
		writeError(w, errStudentNotFound())
		return
	}
	coachID, err := h.planCoachFor(r.Context(), claims, studentID)
	if err != nil {
		h.logger.Error("coach_link_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	dup, err := h.plans.DuplicatePlan(r.Context(), repo.DuplicateParams{
		TenantID: claims.TenantID, SourcePlanID: src.ID, StudentID: studentID, CoachID: coachID,
	})
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case err != nil:
		var unknown repo.UnknownExerciseError
		if errors.As(err, &unknown) {
			writeError(w, errUnknownExercise(unknown.ExerciseID))
			return
		}
		h.logger.Error("plan_duplicate_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	h.writePlan(w, r, claims.TenantID, dup, http.StatusCreated)
}

// Archive responde POST /v1/plans/{id}/archive. O plano ativo do aluno não
// arquiva (409 plan_is_active): ative outro antes. Idempotente.
func (h *PlanHandler) Archive(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	plan, apiErr := h.loadStudentPlan(r, claims)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	plan, err := h.plans.ArchivePlan(r.Context(), claims.TenantID, plan.ID)
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.Is(err, repo.ErrPlanIsActive):
		writeError(w, errPlanIsActive())
		return
	case err != nil:
		h.logger.Error("plan_archive_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	h.writePlan(w, r, claims.TenantID, plan, http.StatusOK)
}

// Activate responde POST /v1/students/{id}/plans/{plan_id}/activate: o plano
// passa a ser o ativo do aluno, na última versão publicada, e a rotação
// recomeça no primeiro dia. O vínculo é checado pelo middleware da rota.
func (h *PlanHandler) Activate(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	studentID, planID := chi.URLParam(r, "id"), chi.URLParam(r, "plan_id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	if _, err := uuid.Parse(planID); err != nil {
		writeError(w, errValidation("plan_id"))
		return
	}
	state, err := h.plans.ActivatePlan(r.Context(), tenantID, studentID, planID)
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.Is(err, repo.ErrPlanNotPublished):
		writeError(w, errPlanNotPublished())
		return
	case err != nil:
		h.logger.Error("plan_activate_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, h.rotation(r, tenantID, state))
}

// Versions responde GET /v1/plans/{id}/versions: o histórico do plano com
// autor e tamanho de cada versão. O conteúdo de uma versão sai de
// GET /plans/{id}?version=N.
func (h *PlanHandler) Versions(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	plan, apiErr := h.loadPlan(r.Context(), claims.TenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if apiErr := h.authorizePlan(r.Context(), claims, plan, false); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	versions, err := h.plans.ListVersionSummaries(r.Context(), claims.TenantID, plan.ID)
	if err != nil {
		h.logger.Error("plan_versions_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	items := make([]versionSummaryDTO, 0, len(versions))
	for _, v := range versions {
		items = append(items, versionSummaryDTO{
			versionRefDTO: versionRef(v.PlanVersion), PublishedBy: v.PublishedBy,
			DaysCount: v.DaysCount, ExercisesCount: v.ExercisesCount,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// SetNextDay responde PUT /v1/students/{id}/plan/next-day: o coach escolhe o
// próximo dia da rotação do aluno (ADR-004 §3). O dia tem de ser da versão
// ativa; o aluno enxerga a troca no /me/today e no pull.
func (h *PlanHandler) SetNextDay(w http.ResponseWriter, r *http.Request) {
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
	var req nextDayRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	dayID := strings.TrimSpace(req.DayID)
	if _, err := uuid.Parse(dayID); err != nil {
		writeError(w, errValidation("day_id"))
		return
	}
	state, err := h.plans.SetNextDay(r.Context(), tenantID, studentID, dayID)
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.Is(err, repo.ErrDayNotInPlan):
		writeError(w, errDayNotInPlan(dayID))
		return
	case err != nil:
		h.logger.Error("next_day_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, h.rotation(r, tenantID, state))
}

// rotation serializa a rotação com o rótulo do próximo dia.
func (h *PlanHandler) rotation(r *http.Request, tenantID string, state domain.StudentPlanState) rotationDTO {
	dto := rotationDTO{PlanID: state.PlanID, ActiveVersionID: state.ActiveVersionID}
	if state.NextDayID == nil {
		return dto
	}
	dto.NextDayID = *state.NextDayID
	days, err := h.plans.GetVersionTree(r.Context(), tenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("rotation_tree_failed", slog.Any("error", err))
		return dto
	}
	for _, d := range days {
		if d.ID == dto.NextDayID {
			dto.NextDayLabel = d.Label
			break
		}
	}
	return dto
}

// writePlan responde com o plano (cabeçalho + histórico, sem a árvore).
func (h *PlanHandler) writePlan(w http.ResponseWriter, r *http.Request, tenantID string, plan domain.Plan, status int) {
	resp, apiErr := h.buildResponse(r.Context(), tenantID, plan, nil, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, status, resp)
}
