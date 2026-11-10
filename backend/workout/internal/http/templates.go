package http

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// Modelos de treino (ADR-018, P6.1). Ler e editar a árvore reusa as rotas de
// plano (`/plans/{id}`, `/draft`, `/publish`), que aceitam kind=template; aqui
// ficam a biblioteca, o arquivamento e a atribuição/reaplicação por cópia.

// maxBatchPlans é o teto de alunos (assign) ou planos (reapply) por chamada.
const maxBatchPlans = 50

type createTemplateRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
}

type templateSummaryDTO struct {
	ID                 string    `json:"id"`
	CoachID            string    `json:"coach_id"`
	Title              string    `json:"title"`
	Description        string    `json:"description,omitempty"`
	Status             string    `json:"status"`
	LatestVersionNo    int       `json:"latest_version_no"`
	PublishedVersionNo int       `json:"published_version_no"`
	HasDraft           bool      `json:"has_draft"`
	DaysCount          int       `json:"days_count"`
	ExercisesCount     int       `json:"exercises_count"`
	AssignedCount      int       `json:"assigned_count"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// batchItemDTO é o resultado de um item de assign/reapply: o lote nunca falha
// por causa de um item, cada um carrega o próprio erro (`code` + `params`).
type batchItemDTO struct {
	StudentID string    `json:"student_id,omitempty"`
	PlanID    string    `json:"plan_id,omitempty"`
	VersionNo int       `json:"version_no,omitempty"`
	OK        bool      `json:"ok"`
	Error     *APIError `json:"error,omitempty"`
}

type recipientDTO struct {
	PlanID            string    `json:"plan_id"`
	StudentID         string    `json:"student_id"`
	Title             string    `json:"title"`
	Status            string    `json:"status"`
	IsActive          bool      `json:"is_active"`
	SourceVersionNo   int       `json:"source_version_no"`
	EditedAfterSource bool      `json:"edited_after_source"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// CreateTemplate responde POST /v1/templates: modelo novo em rascunho, do
// ator. A árvore entra pelo `PUT /v1/plans/{id}/draft`.
func (h *PlanHandler) CreateTemplate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req createTemplateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	title, description := strings.TrimSpace(req.Title), strings.TrimSpace(req.Description)
	if title == "" || len(title) > maxPlanTitleLen {
		writeError(w, errValidation("title"))
		return
	}
	if len(description) > maxDescriptionLen {
		writeError(w, errValidation("description"))
		return
	}

	plan, err := h.plans.CreatePlan(r.Context(), domain.Plan{
		TenantID: claims.TenantID, CoachID: claims.Subject, Title: title,
		Description: description, Kind: domain.PlanKindTemplate,
	})
	if err != nil {
		h.logger.Error("template_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, plan, nil, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

// ListTemplates responde GET /v1/templates?q=&status=&cursor=&limit=. Sem
// `status` vêm os ativos; `archived` e `all` ampliam. Todo coach do tenant lista.
func (h *PlanHandler) ListTemplates(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	q := r.URL.Query()
	filter := repo.TemplateFilter{Query: strings.TrimSpace(q.Get("q")), Limit: 30}
	switch status := q.Get("status"); status {
	case "", "archived", "all":
		filter.Status = status
	default:
		writeError(w, errValidation("status"))
		return
	}
	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 100 {
			writeError(w, errValidation("limit"))
			return
		}
		filter.Limit = n
	}
	if raw := q.Get("cursor"); raw != "" {
		key, id, err := decodeCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		at, err := time.Parse(time.RFC3339Nano, key)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		filter.CursorUpdatedAt, filter.CursorID = &at, id
	}

	items, hasMore, err := h.plans.ListTemplates(r.Context(), claims.TenantID, filter)
	if err != nil {
		h.logger.Error("templates_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	out := make([]templateSummaryDTO, 0, len(items))
	for _, t := range items {
		out = append(out, templateSummaryDTO{
			ID: t.ID, CoachID: t.CoachID, Title: t.Title, Description: t.Description,
			Status: string(t.Status), LatestVersionNo: t.LatestVersionNo,
			PublishedVersionNo: t.PublishedVersionNo, HasDraft: t.HasDraft,
			DaysCount: t.DaysCount, ExercisesCount: t.ExercisesCount, AssignedCount: t.AssignedCount,
			CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt,
		})
	}
	resp := map[string]any{"items": out}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp["next_cursor"] = encodeCursor(last.UpdatedAt.UTC().Format(time.RFC3339Nano), last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// ArchiveTemplate responde POST /v1/templates/{id}/archive (autor ou owner).
// Idempotente; os planos já atribuídos não mudam (sem vínculo vivo).
func (h *PlanHandler) ArchiveTemplate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	tpl, apiErr := h.loadTemplate(r, claims.TenantID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if tpl.CoachID != claims.Subject && !hasRole(claims, "owner") {
		writeError(w, errTemplateNotOwned())
		return
	}
	if err := h.plans.ArchiveTemplate(r.Context(), claims.TenantID, tpl.ID); err != nil {
		h.logger.Error("template_archive_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	tpl, apiErr = h.loadPlan(r.Context(), claims.TenantID, tpl.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, tpl, nil, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// UnarchiveTemplate responde POST /v1/templates/{id}/unarchive: o inverso do
// arquivar, com a mesma permissão (autor ou owner) e também idempotente.
func (h *PlanHandler) UnarchiveTemplate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	tpl, apiErr := h.loadTemplate(r, claims.TenantID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if tpl.CoachID != claims.Subject && !hasRole(claims, "owner") {
		writeError(w, errTemplateNotOwned())
		return
	}
	if err := h.plans.UnarchiveTemplate(r.Context(), claims.TenantID, tpl.ID); err != nil {
		h.logger.Error("template_unarchive_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	tpl, apiErr = h.loadPlan(r.Context(), claims.TenantID, tpl.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, tpl, nil, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

type assignRequest struct {
	StudentIDs []string `json:"student_ids"`
	Publish    bool     `json:"publish"`
}

// AssignTemplate responde POST /v1/templates/{id}/assign: cópia profunda da
// última versão publicada para um plano novo de cada aluno, uma transação por
// aluno. Aluno fora do vínculo vira `student_not_found` naquele item, sem
// derrubar o lote. Com publish=true o plano entra direto na rotação.
func (h *PlanHandler) AssignTemplate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req assignRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	studentIDs, ok := uniqueUUIDs(req.StudentIDs)
	if !ok || len(studentIDs) == 0 || len(studentIDs) > maxBatchPlans {
		writeError(w, errValidation("student_ids"))
		return
	}

	tpl, apiErr := h.loadTemplate(r, claims.TenantID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	if tpl.Status == domain.PlanStatusArchived {
		writeError(w, errTemplateArchived())
		return
	}
	version, days, apiErr := h.publishedTree(r, claims.TenantID, tpl.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	visible, err := h.linker.VisibleStudents(r.Context(), claims.TenantID, claims.Subject, claims.Roles, studentIDs)
	if err != nil {
		h.logger.Error("coach_link_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	canSee := toSet(visible)
	// Existência no identity, em lote, só dos que o ator pode ver.
	existing, err := h.existingStudents(r.Context(), claims.TenantID, visible)
	if err != nil {
		h.logger.Error("student_lookup_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	items := make([]batchItemDTO, 0, len(studentIDs))
	for _, studentID := range studentIDs {
		item := batchItemDTO{StudentID: studentID}
		_, visibleOK := canSee[studentID]
		_, exists := existing[studentID]
		if !visibleOK || !exists {
			e := errStudentNotFound()
			item.Error = &e
			items = append(items, item)
			continue
		}
		// O plano fica com o professor vinculado ao aluno, não com quem atribuiu.
		coachID, err := h.planCoachFor(r.Context(), claims, studentID)
		if err != nil {
			h.logger.Error("coach_link_check_failed", slog.Any("error", err))
			e := errInternal()
			item.Error = &e
			items = append(items, item)
			continue
		}
		plan, err := h.plans.AssignTemplate(r.Context(), repo.AssignParams{
			TenantID: claims.TenantID, CoachID: coachID, ActorID: claims.Subject, StudentID: studentID,
			Template: tpl, TemplateVersion: version, Days: days, Publish: req.Publish,
		})
		if err != nil {
			item.Error = h.batchError(err, "template_assign_failed")
			items = append(items, item)
			continue
		}
		item.OK, item.PlanID = true, plan.ID
		items = append(items, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// ListRecipients responde GET /v1/templates/{id}/recipients: os planos que
// nasceram do modelo, com a versão do modelo aplicada e se o plano foi editado
// depois. O coach só enxerga os alunos vinculados a ele (ADR-016).
func (h *PlanHandler) ListRecipients(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	tpl, apiErr := h.loadTemplate(r, claims.TenantID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	recipients, err := h.plans.ListRecipients(r.Context(), claims.TenantID, tpl.ID)
	if err != nil {
		h.logger.Error("template_recipients_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	studentIDs := make([]string, 0, len(recipients))
	for _, rc := range recipients {
		studentIDs = append(studentIDs, rc.StudentID)
	}
	visible, err := h.linker.VisibleStudents(r.Context(), claims.TenantID, claims.Subject, claims.Roles, studentIDs)
	if err != nil {
		h.logger.Error("coach_link_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	canSee := toSet(visible)

	// Versão atual do modelo: o app compara com `source_version_no` para
	// marcar quem está desatualizado. 0 = modelo ainda sem versão publicada.
	templateVersionNo := 0
	if v, err := h.plans.LatestPublishedVersion(r.Context(), claims.TenantID, tpl.ID); err == nil {
		templateVersionNo = v.VersionNo
	} else if !errors.Is(err, repo.ErrNotFound) {
		h.logger.Error("template_version_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	items := make([]recipientDTO, 0, len(recipients))
	for _, rc := range recipients {
		if _, ok := canSee[rc.StudentID]; !ok {
			continue
		}
		items = append(items, recipientDTO{
			PlanID: rc.ID, StudentID: rc.StudentID, Title: rc.Title, Status: string(rc.Status),
			IsActive: rc.IsActive, SourceVersionNo: rc.SourceVersionNo,
			EditedAfterSource: rc.EditedAfterSource, UpdatedAt: rc.UpdatedAt,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"template_version_no": templateVersionNo, "items": items})
}

type reapplyRequest struct {
	PlanIDs []string `json:"plan_ids"`
}

// ReapplyTemplate responde POST /v1/templates/{id}/reapply: para cada plano
// escolhido, troca o rascunho pela última versão publicada do modelo e publica
// versão nova (ADR-018). Os ajustes individuais daquele plano se perdem — o app
// avisa. Resultado por item.
func (h *PlanHandler) ReapplyTemplate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req reapplyRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	planIDs, ok := uniqueUUIDs(req.PlanIDs)
	if !ok || len(planIDs) == 0 || len(planIDs) > maxBatchPlans {
		writeError(w, errValidation("plan_ids"))
		return
	}

	tpl, apiErr := h.loadTemplate(r, claims.TenantID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	version, days, apiErr := h.publishedTree(r, claims.TenantID, tpl.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	// Carrega os planos antes para checar o vínculo de todos os alunos numa
	// consulta só.
	plans := make(map[string]domain.Plan, len(planIDs))
	studentIDs := make([]string, 0, len(planIDs))
	for _, id := range planIDs {
		plan, err := h.plans.GetPlan(r.Context(), claims.TenantID, id)
		if errors.Is(err, repo.ErrNotFound) {
			continue
		}
		if err != nil {
			h.logger.Error("plan_get_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		plans[id] = plan
		if plan.StudentID != "" {
			studentIDs = append(studentIDs, plan.StudentID)
		}
	}
	visible, err := h.linker.VisibleStudents(r.Context(), claims.TenantID, claims.Subject, claims.Roles, studentIDs)
	if err != nil {
		h.logger.Error("coach_link_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	canSee := toSet(visible)

	items := make([]batchItemDTO, 0, len(planIDs))
	for _, id := range planIDs {
		item := batchItemDTO{PlanID: id}
		plan, found := plans[id]
		if !found {
			e := errNotFound("plan")
			item.Error = &e
			items = append(items, item)
			continue
		}
		item.StudentID = plan.StudentID
		// Plano de outro modelo (ou um modelo) não é destinatário; só depois
		// o vínculo, para não revelar a procedência de plano de aluno alheio.
		if _, ok := canSee[plan.StudentID]; !ok {
			e := errStudentNotFound()
			item.Error = &e
			item.StudentID = ""
			items = append(items, item)
			continue
		}
		v, err := h.plans.ReapplyTemplate(r.Context(), repo.ReapplyParams{
			TenantID: claims.TenantID, ActorID: claims.Subject, PlanID: id, Template: tpl, TemplateVersion: version, Days: days,
		})
		if err != nil {
			item.Error = h.batchError(err, "template_reapply_failed")
			items = append(items, item)
			continue
		}
		item.OK, item.VersionNo = true, v.VersionNo
		items = append(items, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

type saveAsTemplateRequest struct {
	Title string `json:"title"`
}

// SaveAsTemplate responde POST /v1/plans/{id}/save-as-template: copia a versão
// mais recente do plano do aluno (rascunho aberto ou última publicada) para um
// modelo novo, em rascunho — o coach revisa e publica antes de atribuir.
func (h *PlanHandler) SaveAsTemplate(w http.ResponseWriter, r *http.Request) {
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
	if plan.Kind == domain.PlanKindTemplate {
		writeError(w, errNotFound("plan"))
		return
	}
	if apiErr := h.authorizePlan(r.Context(), claims, plan, false); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	var req saveAsTemplateRequest
	// Corpo opcional: sem título usa o do plano.
	if r.ContentLength != 0 {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			writeError(w, errInvalidBody())
			return
		}
	}
	title := strings.TrimSpace(req.Title)
	if len(title) > maxPlanTitleLen {
		writeError(w, errValidation("title"))
		return
	}

	tpl, err := h.plans.SaveAsTemplate(r.Context(), repo.SaveAsTemplateParams{
		TenantID: claims.TenantID, CoachID: claims.Subject, SourcePlanID: plan.ID, Title: title,
	})
	var incomplete repo.IncompletePlanError
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.As(err, &incomplete):
		writeError(w, errPlanIncomplete(incomplete.Reason, ""))
		return
	case err != nil:
		h.logger.Error("save_as_template_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	version, apiErr := h.resolveVersion(r, claims.TenantID, tpl.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, tpl, version, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

// loadTemplate lê o modelo da URL: plano de aluno com esse id é 404, como se
// o modelo não existisse (as duas famílias de rota não se misturam).
func (h *PlanHandler) loadTemplate(r *http.Request, tenantID string) (domain.Plan, *APIError) {
	plan, apiErr := h.loadPlan(r.Context(), tenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		return domain.Plan{}, apiErr
	}
	if plan.Kind != domain.PlanKindTemplate {
		e := errNotFound("template")
		return domain.Plan{}, &e
	}
	return plan, nil
}

// publishedTree lê a última versão publicada do modelo e a árvore dela;
// `template_not_published` (422) se ainda não há nenhuma.
func (h *PlanHandler) publishedTree(r *http.Request, tenantID, templateID string) (domain.PlanVersion, []domain.Day, *APIError) {
	version, err := h.plans.LatestPublishedVersion(r.Context(), tenantID, templateID)
	if errors.Is(err, repo.ErrNotFound) {
		e := errTemplateNotPublished()
		return domain.PlanVersion{}, nil, &e
	}
	if err != nil {
		h.logger.Error("template_version_failed", slog.Any("error", err))
		e := errInternal()
		return domain.PlanVersion{}, nil, &e
	}
	days, err := h.plans.GetVersionTree(r.Context(), tenantID, version.ID)
	if err != nil {
		h.logger.Error("template_tree_failed", slog.Any("error", err))
		e := errInternal()
		return domain.PlanVersion{}, nil, &e
	}
	return version, days, nil
}

// batchError traduz o erro de um item de lote.
func (h *PlanHandler) batchError(err error, logKey string) *APIError {
	var unknown repo.UnknownExerciseError
	var e APIError
	switch {
	case errors.Is(err, repo.ErrNotFound):
		e = errNotFound("plan")
	case errors.Is(err, repo.ErrNotRecipient):
		e = errPlanNotFromTemplate()
	case errors.Is(err, repo.ErrPlanArchived):
		e = errPlanArchived()
	case errors.As(err, &unknown):
		e = errUnknownExercise(unknown.ExerciseID)
	default:
		h.logger.Error(logKey, slog.Any("error", err))
		e = errInternal()
	}
	return &e
}

// uniqueUUIDs valida e deduplica preservando a ordem; false se algum não é UUID.
func uniqueUUIDs(in []string) ([]string, bool) {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, raw := range in {
		id := strings.TrimSpace(raw)
		if _, err := uuid.Parse(id); err != nil {
			return nil, false
		}
		if _, dup := seen[id]; dup {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out, true
}

func toSet(ids []string) map[string]struct{} {
	set := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		set[id] = struct{}{}
	}
	return set
}
