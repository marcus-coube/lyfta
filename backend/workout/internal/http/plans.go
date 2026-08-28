package http

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
	"github.com/marcus-coube/lyfta/workout/internal/security"
)

// PlanHandler expõe o builder do professor e a atribuição ao aluno (P1.4):
// rascunho editável, publicação que congela a versão (ADR-004 §1) e a leitura
// do plano ativo pelo aluno.
type PlanHandler struct {
	// planView é a leitura do plano (árvore serializada + histórico de
	// versões), compartilhada com o handler de execução do P1.5: o dia que o
	// aluno executa tem de ser, campo a campo, o dia que o coach montou.
	planView
}

// NewPlanHandler cria o handler do builder.
func NewPlanHandler(logger *slog.Logger, plans *repo.PlanRepo, exercises *repo.ExerciseRepo, presigner *media.Presigner) *PlanHandler {
	return &PlanHandler{planView: newPlanView(logger, plans, exercises, presigner)}
}

// Limites da árvore enviada pelo builder. Não são regra de negócio, são teto
// de payload: sem eles um POST de 50 MB de JSON vira milhares de INSERTs numa
// transação só.
const (
	maxPlanTitleLen      = 120
	maxDayLabelLen       = 8
	maxDayTitleLen       = 120
	maxNotesLen          = 500
	maxTempoLen          = 16
	maxDays              = 14
	maxBlocksPerDay      = 30
	maxExercisesPerBlock = 12
	maxSetsPerExercise   = 20
	maxRestSeconds       = 3600
	maxReps              = 1000
	maxTargetValue       = 1000
)

type createPlanRequest struct {
	StudentID string `json:"student_id"`
	CoachID   string `json:"coach_id"`
	Title     string `json:"title"`
}

type setDTO struct {
	ID           string   `json:"id,omitempty"`
	SetNo        int      `json:"set_no,omitempty"`
	RepsMin      *int     `json:"reps_min"`
	RepsMax      *int     `json:"reps_max"`
	TargetLoadKg *float64 `json:"target_load_kg"`
	TargetUnit   string   `json:"target_unit,omitempty"`
	TargetValue  *float64 `json:"target_value"`
	RestSeconds  *int     `json:"rest_seconds"`
	Tempo        string   `json:"tempo,omitempty"`
}

type blockExerciseDTO struct {
	ID         string           `json:"id,omitempty"`
	ExerciseID string           `json:"exercise_id"`
	Position   int              `json:"position"`
	Notes      string           `json:"notes,omitempty"`
	Exercise   *exerciseSummary `json:"exercise,omitempty"`
	Sets       []setDTO         `json:"sets"`
}

type blockDTO struct {
	ID          string             `json:"id,omitempty"`
	Position    int                `json:"position"`
	BlockType   string             `json:"block_type"`
	RestSeconds int                `json:"rest_seconds"`
	Exercises   []blockExerciseDTO `json:"exercises"`
}

type dayDTO struct {
	ID       string     `json:"id,omitempty"`
	Label    string     `json:"label"`
	Position int        `json:"position"`
	Title    string     `json:"title,omitempty"`
	Blocks   []blockDTO `json:"blocks"`
}

type draftRequest struct {
	Title string   `json:"title"`
	Days  []dayDTO `json:"days"`
}

type versionRefDTO struct {
	ID          string     `json:"id"`
	VersionNo   int        `json:"version_no"`
	PublishedAt *time.Time `json:"published_at"`
	IsDraft     bool       `json:"is_draft"`
}

type versionDTO struct {
	versionRefDTO
	Days []dayDTO `json:"days"`
}

type planResponse struct {
	ID        string    `json:"id"`
	StudentID string    `json:"student_id"`
	CoachID   string    `json:"coach_id"`
	Title     string    `json:"title"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	// Version é a versão carregada (rascunho ou publicada); Versions é o
	// histórico só com os cabeçalhos.
	Version  *versionDTO     `json:"version"`
	Versions []versionRefDTO `json:"versions"`
	// Estado da rotação (ADR-004 §3), presente quando este é o plano ativo
	// do aluno.
	ActiveVersionID string `json:"active_version_id,omitempty"`
	NextDayID       string `json:"next_day_id,omitempty"`
}

type planSummaryDTO struct {
	ID                 string    `json:"id"`
	StudentID          string    `json:"student_id"`
	CoachID            string    `json:"coach_id"`
	Title              string    `json:"title"`
	Status             string    `json:"status"`
	LatestVersionNo    int       `json:"latest_version_no"`
	PublishedVersionNo int       `json:"published_version_no"`
	HasDraft           bool      `json:"has_draft"`
	IsActive           bool      `json:"is_active"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// Create abre um plano em rascunho para o aluno. A versão só nasce quando a
// primeira árvore é salva (PUT /draft) — plano recém-criado não tem conteúdo
// nenhum a versionar.
func (h *PlanHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req createPlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if _, err := uuid.Parse(strings.TrimSpace(req.StudentID)); err != nil {
		writeError(w, errValidation("student_id"))
		return
	}
	title := strings.TrimSpace(req.Title)
	if title == "" || len(title) > maxPlanTitleLen {
		writeError(w, errValidation("title"))
		return
	}
	// Por padrão o autor é o coach do plano. Atribuir o plano a outro
	// professor é ato de administração da academia, então exige owner.
	coachID := claims.Subject
	if raw := strings.TrimSpace(req.CoachID); raw != "" && raw != claims.Subject {
		if _, err := uuid.Parse(raw); err != nil {
			writeError(w, errValidation("coach_id"))
			return
		}
		if !hasRole(claims, "owner") {
			writeError(w, errForbidden())
			return
		}
		coachID = raw
	}

	plan, err := h.plans.CreatePlan(r.Context(), domain.Plan{
		TenantID:  claims.TenantID,
		StudentID: strings.TrimSpace(req.StudentID),
		CoachID:   coachID,
		Title:     title,
	})
	if err != nil {
		h.logger.Error("plan_create_failed", slog.Any("error", err))
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

// Get devolve o plano com uma versão carregada. `?version=` aceita `draft`,
// `latest` ou o número da versão; sem ele vem o rascunho, se houver, e a
// última publicada caso contrário — que é o que a tela do coach abre.
func (h *PlanHandler) Get(w http.ResponseWriter, r *http.Request) {
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

	version, apiErr := h.resolveVersion(r, claims.TenantID, plan.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, plan, version, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// UpdateDraft substitui a árvore inteira do rascunho (dias → blocos →
// exercícios → sets). Se a última versão do plano já está publicada, um
// rascunho novo é aberto: é assim que editar um plano publicado vira v2 sem
// tocar na v1 (ADR-004 §1).
func (h *PlanHandler) UpdateDraft(w http.ResponseWriter, r *http.Request) {
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
	if apiErr := authorizeWrite(claims, plan); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	var req draftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	days, apiErr := parseDays(req.Days)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	title := strings.TrimSpace(req.Title)
	if len(title) > maxPlanTitleLen {
		writeError(w, errValidation("title"))
		return
	}

	version, _, err := h.plans.ReplaceDraft(r.Context(), claims.TenantID, plan.ID, title, days)
	var unknown repo.UnknownExerciseError
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.As(err, &unknown):
		writeError(w, errUnknownExercise(unknown.ExerciseID))
		return
	case err != nil:
		h.logger.Error("plan_draft_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	// Relê o plano: o título pode ter mudado agora.
	plan, apiErr = h.loadPlan(r.Context(), claims.TenantID, plan.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, plan, &version, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// Publish congela o rascunho e passa a rotação do aluno para ele.
func (h *PlanHandler) Publish(w http.ResponseWriter, r *http.Request) {
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
	if apiErr := authorizeWrite(claims, plan); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	version, _, err := h.plans.PublishDraft(r.Context(), claims.TenantID, plan.ID)
	var incomplete repo.IncompletePlanError
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.Is(err, repo.ErrNoDraft):
		writeError(w, errNoDraft())
		return
	case errors.As(err, &incomplete):
		writeError(w, errPlanIncomplete(incomplete.Reason, incomplete.DayID))
		return
	case err != nil:
		h.logger.Error("plan_publish_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	plan, apiErr = h.loadPlan(r.Context(), claims.TenantID, plan.ID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, plan, &version, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// ListByStudent devolve os planos de um aluno para o coach — o histórico do
// aluno dentro do tenant, com a marca de qual está ativo.
//
// Ler é do tenant inteiro (um professor cobrindo férias do outro precisa ver
// o plano); escrever continua restrito ao coach do plano ou ao owner.
func (h *PlanHandler) ListByStudent(w http.ResponseWriter, r *http.Request) {
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

	plans, err := h.plans.ListPlansByStudent(r.Context(), tenantID, studentID)
	if err != nil {
		h.logger.Error("plans_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	items := make([]planSummaryDTO, 0, len(plans))
	for _, p := range plans {
		items = append(items, planSummaryDTO{
			ID: p.ID, StudentID: p.StudentID, CoachID: p.CoachID, Title: p.Title,
			Status: string(p.Status), LatestVersionNo: p.LatestVersionNo,
			PublishedVersionNo: p.PublishedVersionNo, HasDraft: p.HasDraft,
			IsActive: p.IsActive, CreatedAt: p.CreatedAt, UpdatedAt: p.UpdatedAt,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// MyPlan devolve ao aluno o plano ativo dele, na versão publicada que a
// rotação aponta. O aluno é sempre o `sub` da claim: não há parâmetro de
// aluno aqui, então nenhum token consegue ler o plano de outra pessoa.
func (h *PlanHandler) MyPlan(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	state, err := h.plans.GetState(r.Context(), claims.TenantID, claims.Subject)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("plan"))
		return
	}
	if err != nil {
		h.logger.Error("plan_state_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	plan, apiErr := h.loadPlan(r.Context(), claims.TenantID, state.PlanID)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	version, err := h.plans.GetVersionByID(r.Context(), claims.TenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("plan_version_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp, apiErr := h.buildResponse(r.Context(), claims.TenantID, plan, &version, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp.ActiveVersionID = state.ActiveVersionID
	if state.NextDayID != nil {
		resp.NextDayID = *state.NextDayID
	}
	writeJSON(w, http.StatusOK, resp)
}

// loadPlan lê o plano do tenant traduzindo o erro do repositório.
func (h *PlanHandler) loadPlan(ctx context.Context, tenantID, planID string) (domain.Plan, *APIError) {
	if _, err := uuid.Parse(planID); err != nil {
		apiErr := errValidation("id")
		return domain.Plan{}, &apiErr
	}
	plan, err := h.plans.GetPlan(ctx, tenantID, planID)
	if errors.Is(err, repo.ErrNotFound) {
		apiErr := errNotFound("plan")
		return domain.Plan{}, &apiErr
	}
	if err != nil {
		h.logger.Error("plan_get_failed", slog.Any("error", err))
		apiErr := errInternal()
		return domain.Plan{}, &apiErr
	}
	return plan, nil
}

// resolveVersion escolhe a versão pedida em `?version=`.
func (h *PlanHandler) resolveVersion(r *http.Request, tenantID, planID string) (*domain.PlanVersion, *APIError) {
	var (
		version domain.PlanVersion
		err     error
	)
	switch raw := strings.TrimSpace(r.URL.Query().Get("version")); raw {
	case "":
		version, err = h.plans.LatestVersion(r.Context(), tenantID, planID)
	case "draft":
		version, err = h.plans.DraftVersion(r.Context(), tenantID, planID)
	case "latest":
		version, err = h.plans.LatestVersion(r.Context(), tenantID, planID)
	default:
		versionNo, convErr := strconv.Atoi(raw)
		if convErr != nil || versionNo <= 0 {
			apiErr := errValidation("version")
			return nil, &apiErr
		}
		version, err = h.plans.VersionByNo(r.Context(), tenantID, planID, versionNo)
	}
	if errors.Is(err, repo.ErrNotFound) {
		// Plano sem nenhuma versão ainda (ou pedido de rascunho inexistente)
		// não é erro: é plano vazio.
		return nil, nil
	}
	if err != nil {
		h.logger.Error("plan_version_failed", slog.Any("error", err))
		apiErr := errInternal()
		return nil, &apiErr
	}
	return &version, nil
}

// parseDays valida a árvore recebida e a converte para o domínio. Posição e
// número do set saem da **ordem do array**: o cliente reordena movendo itens
// na lista, e o servidor não precisa confiar em índices enviados à mão.
func parseDays(days []dayDTO) ([]domain.Day, *APIError) {
	if len(days) > maxDays {
		return nil, fail("days")
	}
	out := make([]domain.Day, 0, len(days))
	labels := map[string]struct{}{}

	for di, d := range days {
		prefix := "days[" + strconv.Itoa(di) + "]"
		label := strings.TrimSpace(d.Label)
		if label == "" || len(label) > maxDayLabelLen {
			return nil, fail(prefix + ".label")
		}
		if _, dup := labels[label]; dup {
			// O banco também recusa (UNIQUE plan_version_id, label), mas com
			// erro de constraint; aqui o coach descobre qual dia repetiu.
			return nil, fail(prefix + ".label")
		}
		labels[label] = struct{}{}
		title := strings.TrimSpace(d.Title)
		if len(title) > maxDayTitleLen {
			return nil, fail(prefix + ".title")
		}
		if len(d.Blocks) > maxBlocksPerDay {
			return nil, fail(prefix + ".blocks")
		}

		day := domain.Day{Label: label, Position: di, Title: title, Blocks: make([]domain.Block, 0, len(d.Blocks))}
		for bi, b := range d.Blocks {
			blockPrefix := prefix + ".blocks[" + strconv.Itoa(bi) + "]"
			blockType := domain.BlockType(strings.TrimSpace(b.BlockType))
			if blockType == "" {
				blockType = domain.BlockTypeStraight
			}
			if !domain.IsValidBlockType(blockType) {
				return nil, fail(blockPrefix + ".block_type")
			}
			if b.RestSeconds < 0 || b.RestSeconds > maxRestSeconds {
				return nil, fail(blockPrefix + ".rest_seconds")
			}
			if len(b.Exercises) > maxExercisesPerBlock {
				return nil, fail(blockPrefix + ".exercises")
			}

			block := domain.Block{
				Position: bi, BlockType: blockType, RestSeconds: b.RestSeconds,
				Exercises: make([]domain.BlockExercise, 0, len(b.Exercises)),
			}
			for ei, e := range b.Exercises {
				exPrefix := blockPrefix + ".exercises[" + strconv.Itoa(ei) + "]"
				exerciseID := strings.TrimSpace(e.ExerciseID)
				if _, err := uuid.Parse(exerciseID); err != nil {
					return nil, fail(exPrefix + ".exercise_id")
				}
				notes := strings.TrimSpace(e.Notes)
				if len(notes) > maxNotesLen {
					return nil, fail(exPrefix + ".notes")
				}
				if len(e.Sets) > maxSetsPerExercise {
					return nil, fail(exPrefix + ".sets")
				}

				be := domain.BlockExercise{
					ExerciseID: exerciseID, Position: ei, Notes: notes,
					Sets: make([]domain.PrescribedSet, 0, len(e.Sets)),
				}
				for si, s := range e.Sets {
					set, apiErr := parseSet(s, exPrefix+".sets["+strconv.Itoa(si)+"]")
					if apiErr != nil {
						return nil, apiErr
					}
					set.SetNo = si + 1
					be.Sets = append(be.Sets, set)
				}
				block.Exercises = append(block.Exercises, be)
			}
			day.Blocks = append(day.Blocks, block)
		}
		out = append(out, day)
	}
	return out, nil
}

// parseSet valida a prescrição estruturada de uma série (ADR-012 §4). São as
// mesmas regras dos CHECKs da tabela, verificadas antes para o coach receber
// um erro traduzível em vez de 500 vindo do banco.
func parseSet(s setDTO, prefix string) (domain.PrescribedSet, *APIError) {
	set := domain.PrescribedSet{
		RepsMin: s.RepsMin, RepsMax: s.RepsMax, TargetLoadKg: s.TargetLoadKg,
		TargetValue: s.TargetValue, RestSeconds: s.RestSeconds,
		Tempo: strings.TrimSpace(s.Tempo),
	}

	if s.RepsMin != nil && (*s.RepsMin < 0 || *s.RepsMin > maxReps) {
		return domain.PrescribedSet{}, fail(prefix + ".reps_min")
	}
	if s.RepsMax != nil && (*s.RepsMax < 0 || *s.RepsMax > maxReps) {
		return domain.PrescribedSet{}, fail(prefix + ".reps_max")
	}
	if s.RepsMin != nil && s.RepsMax != nil && *s.RepsMax < *s.RepsMin {
		return domain.PrescribedSet{}, fail(prefix + ".reps_max")
	}
	if s.TargetLoadKg != nil && (*s.TargetLoadKg < 0 || *s.TargetLoadKg > maxTargetValue) {
		return domain.PrescribedSet{}, fail(prefix + ".target_load_kg")
	}
	if s.TargetValue != nil && (*s.TargetValue < 0 || *s.TargetValue > maxTargetValue) {
		return domain.PrescribedSet{}, fail(prefix + ".target_value")
	}
	if s.RestSeconds != nil && (*s.RestSeconds < 0 || *s.RestSeconds > maxRestSeconds) {
		return domain.PrescribedSet{}, fail(prefix + ".rest_seconds")
	}
	if len(set.Tempo) > maxTempoLen {
		return domain.PrescribedSet{}, fail(prefix + ".tempo")
	}

	if unit := domain.TargetUnit(strings.TrimSpace(s.TargetUnit)); unit != "" {
		if !domain.IsValidTargetUnit(unit) {
			return domain.PrescribedSet{}, fail(prefix + ".target_unit")
		}
		// Alvo relativo (%1RM/RPE/RIR) sem valor não prescreve nada — é o
		// CHECK prescribed_sets_target_complete.
		if unit != domain.TargetUnitKg && s.TargetValue == nil {
			return domain.PrescribedSet{}, fail(prefix + ".target_value")
		}
		set.TargetUnit = &unit
	}
	return set, nil
}

// versionRef serializa o cabeçalho de uma versão.
func versionRef(v domain.PlanVersion) versionRefDTO {
	return versionRefDTO{
		ID: v.ID, VersionNo: v.VersionNo, PublishedAt: v.PublishedAt, IsDraft: v.PublishedAt == nil,
	}
}

// authorizeWrite aplica o "só coach do aluno edita" do P1.4 com o que existe
// dentro deste serviço: o coach dono do plano, ou o owner do tenant.
func authorizeWrite(claims *security.Claims, plan domain.Plan) *APIError {
	if plan.CoachID == claims.Subject || hasRole(claims, "owner") {
		return nil
	}
	apiErr := errForbidden()
	return &apiErr
}

func hasRole(claims *security.Claims, role string) bool {
	for _, r := range claims.Roles {
		if r == role {
			return true
		}
	}
	return false
}

func fail(field string) *APIError {
	apiErr := errValidation(field)
	return &apiErr
}

// requestLocaleOrDefault é requestLocale sem o erro: aqui um `?locale=`
// inválido não deve derrubar a leitura do plano.
func requestLocaleOrDefault(r *http.Request) domain.Locale {
	locale, apiErr := requestLocale(r)
	if apiErr != nil {
		return domain.LocaleSource
	}
	return locale
}
