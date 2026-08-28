package http

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// SyncHandler é o contrato offline inteiro do lado servidor (P1.5, ADR-003):
// o treino do dia num payload cacheável, o push idempotente da fila de
// eventos, o pull incremental e o override manual da rotação.
type SyncHandler struct {
	planView
	sessions *repo.SessionRepo
}

// NewSyncHandler cria o handler de execução e sync.
func NewSyncHandler(logger *slog.Logger, plans *repo.PlanRepo, sessions *repo.SessionRepo, exercises *repo.ExerciseRepo, presigner *media.Presigner) *SyncHandler {
	return &SyncHandler{planView: newPlanView(logger, plans, exercises, presigner), sessions: sessions}
}

// Limites do lote e sanidade do relógio do device.
const (
	// maxSyncEvents é o teto de eventos por lote. Uma sessão de treino inteira
	// cabe folgado; o teto existe para o lote não virar uma transação
	// arbitrariamente longa.
	maxSyncEvents = 200
	// maxClockSkew é a folga aceita para `performed_at` no futuro (ADR-003:
	// "relógio do device não é confiável"). Um device com o fuso errado manda
	// horas para a frente e envenenaria o histórico e o gráfico de carga.
	maxClockSkew = 24 * time.Hour
	// maxPullPageSize é o teto de exercícios por página do pull.
	maxPullPageSize = 100
	// pullWatermarkLag recua a marca d'água do pull alguns segundos. Uma
	// transação que começou antes do `now()` da consulta mas comitou depois
	// ficaria invisível para sempre com uma marca exata; o custo do recuo é
	// reenviar algo já sincronizado, que é idempotente do lado do device.
	pullWatermarkLag = 5 * time.Second
)

// Estados da tela Hoje. São códigos, não texto: quem traduz é o app
// (ADR-011 §5).
const (
	todayStatusNoPlan  = "no_plan"
	todayStatusRestDay = "rest_day"
	todayStatusReady   = "ready"
)

type todayPlanDTO struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	VersionID   string     `json:"version_id"`
	VersionNo   int        `json:"version_no"`
	PublishedAt *time.Time `json:"published_at"`
}

type previousLoadSetDTO struct {
	SetNo    int      `json:"set_no"`
	RepsDone *int     `json:"reps_done"`
	LoadKg   *float64 `json:"load_kg"`
	RPE      *float64 `json:"rpe"`
}

type previousLoadDTO struct {
	ExerciseID  string               `json:"exercise_id"`
	SessionID   string               `json:"session_id"`
	PerformedAt time.Time            `json:"performed_at"`
	Sets        []previousLoadSetDTO `json:"sets"`
}

type sessionSummaryDTO struct {
	ID            string     `json:"id"`
	DayLabel      string     `json:"day_label"`
	StartedAt     time.Time  `json:"started_at"`
	FinishedAt    *time.Time `json:"finished_at"`
	TotalSets     int        `json:"total_sets"`
	TotalVolumeKg float64    `json:"total_volume_kg"`
}

// todayResponse é pensado para ser cacheado **inteiro** no device (ADR-003
// §3): tudo que a tela Hoje e o player de execução precisam sai desta única
// chamada, porque a próxima pode acontecer sem rede.
type todayResponse struct {
	Status         string              `json:"status"`
	Plan           *todayPlanDTO       `json:"plan"`
	Day            *dayDTO             `json:"day"`
	PreviousLoads  []previousLoadDTO   `json:"previous_loads"`
	RecentSessions []sessionSummaryDTO `json:"recent_sessions"`
	ServerTime     time.Time           `json:"server_time"`
}

// Today resolve a rotação do aluno e devolve o dia que ele tem de fazer.
//
// O aluno é sempre o `sub` da claim: não há parâmetro de aluno, então nenhum
// token lê o treino de outra pessoa.
func (h *SyncHandler) Today(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	ctx := r.Context()
	resp := todayResponse{
		Status:         todayStatusNoPlan,
		PreviousLoads:  []previousLoadDTO{},
		RecentSessions: []sessionSummaryDTO{},
		ServerTime:     time.Now().UTC(),
	}

	// Aluno sem plano não é erro, é um estado da tela: 404 obrigaria o app a
	// tratar exceção para desenhar "seu professor ainda não montou seu
	// treino", e o cache local guardaria um erro.
	state, err := h.plans.GetState(ctx, claims.TenantID, claims.Subject)
	if errors.Is(err, repo.ErrNotFound) {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	if err != nil {
		h.logger.Error("today_state_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	plan, err := h.plans.GetPlan(ctx, claims.TenantID, state.PlanID)
	if err != nil {
		h.logger.Error("today_plan_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	version, err := h.plans.GetVersionByID(ctx, claims.TenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("today_version_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp.Plan = &todayPlanDTO{
		ID: plan.ID, Title: plan.Title, VersionID: version.ID,
		VersionNo: version.VersionNo, PublishedAt: version.PublishedAt,
	}

	// Histórico recente e carga anterior não dependem de haver treino hoje —
	// o aluno em dia de descanso continua vendo o que fez na semana.
	recent, err := h.sessions.RecentSessions(ctx, claims.TenantID, claims.Subject, 0)
	if err != nil {
		h.logger.Error("today_recent_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	for _, s := range recent {
		resp.RecentSessions = append(resp.RecentSessions, sessionSummaryDTO{
			ID: s.ID, DayLabel: s.DayLabel, StartedAt: s.StartedAt, FinishedAt: s.FinishedAt,
			TotalSets: s.TotalSets, TotalVolumeKg: s.TotalVolumeKg,
		})
	}

	if state.NextDayID == nil {
		resp.Status = todayStatusRestDay
		writeJSON(w, http.StatusOK, resp)
		return
	}

	days, err := h.plans.GetVersionTree(ctx, claims.TenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("today_tree_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	var today *domain.Day
	for i := range days {
		if days[i].ID == *state.NextDayID {
			today = &days[i]
			break
		}
	}
	if today == nil {
		// A rotação aponta para um dia que não existe mais na versão ativa —
		// não deveria acontecer (publish reancora pelo rótulo), mas devolver
		// descanso é melhor que 500.
		resp.Status = todayStatusRestDay
		writeJSON(w, http.StatusOK, resp)
		return
	}

	dayDTOs, apiErr := h.daysToDTO(ctx, claims.TenantID, []domain.Day{*today}, requestLocaleOrDefault(r))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp.Status, resp.Day = todayStatusReady, &dayDTOs[0]

	previous, err := h.sessions.PreviousLoads(ctx, claims.TenantID, claims.Subject, exerciseIDsOf(*today))
	if err != nil {
		h.logger.Error("today_previous_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	// A ordem segue a do treino, não a do map: a tela lê de cima para baixo.
	for _, id := range exerciseIDsOf(*today) {
		prev, ok := previous[id]
		if !ok {
			continue
		}
		item := previousLoadDTO{
			ExerciseID: prev.ExerciseID, SessionID: prev.SessionID,
			PerformedAt: prev.PerformedAt, Sets: make([]previousLoadSetDTO, 0, len(prev.Sets)),
		}
		for _, s := range prev.Sets {
			item.Sets = append(item.Sets, previousLoadSetDTO{
				SetNo: s.SetNo, RepsDone: s.RepsDone, LoadKg: s.LoadKg, RPE: s.RPE,
			})
		}
		resp.PreviousLoads = append(resp.PreviousLoads, item)
	}

	writeJSON(w, http.StatusOK, resp)
}

type syncEventDTO struct {
	ClientID    string          `json:"client_id"`
	Type        string          `json:"type"`
	PerformedAt time.Time       `json:"performed_at"`
	Payload     json.RawMessage `json:"payload"`
}

type syncPayloadDTO struct {
	DayID           string   `json:"day_id"`
	SessionClientID string   `json:"session_client_id"`
	ExerciseID      string   `json:"exercise_id"`
	SetNo           int      `json:"set_no"`
	RepsDone        *int     `json:"reps_done"`
	LoadKg          *float64 `json:"load_kg"`
	RPE             *float64 `json:"rpe"`
	Revises         string   `json:"revises"`
}

type syncRequest struct {
	Events []syncEventDTO `json:"events"`
}

type syncResultDTO struct {
	ClientID  string `json:"client_id"`
	Status    string `json:"status"`
	Code      string `json:"code,omitempty"`
	Field     string `json:"field,omitempty"`
	SessionID string `json:"session_id,omitempty"`
}

type syncStateDTO struct {
	PlanID          string     `json:"plan_id"`
	ActiveVersionID string     `json:"active_version_id"`
	NextDayID       string     `json:"next_day_id,omitempty"`
	NextDayLabel    string     `json:"next_day_label,omitempty"`
	LastSessionAt   *time.Time `json:"last_session_at"`
}

type syncResponse struct {
	Results    []syncResultDTO `json:"results"`
	Accepted   int             `json:"accepted"`
	Duplicates int             `json:"duplicates"`
	Rejected   int             `json:"rejected"`
	// State é a rotação depois do lote: é assim que o app sabe que o treino
	// de hoje virou B sem precisar de outra chamada (ADR-004 §3).
	State      *syncStateDTO `json:"state"`
	ReceivedAt time.Time     `json:"received_at"`
}

// PushLogs drena um lote da fila offline do device (ADR-003 §4).
//
// O lote nunca falha inteiro por causa de um evento ruim: cada evento volta
// com o próprio desfecho (`accepted`/`duplicate`/`rejected`), e o device apaga
// da fila local tudo que não for erro de rede. Um evento malformado que
// derrubasse o lote deixaria a fila travada para sempre.
func (h *SyncHandler) PushLogs(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req syncRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if len(req.Events) > maxSyncEvents {
		writeError(w, errBatchTooLarge(maxSyncEvents))
		return
	}

	// Eventos válidos vão para o repositório; os malformados já saem
	// rejeitados, na posição que ocupavam no lote.
	events := make([]domain.SyncEvent, 0, len(req.Events))
	rejected := map[int]syncResultDTO{}
	for i, raw := range req.Events {
		ev, field := parseSyncEvent(raw)
		if field == "" {
			events = append(events, ev)
			continue
		}
		if field == "client_id" {
			// Sem client_id não há o que confirmar: o device não conseguiria
			// casar a resposta com a fila dele. Este é o único caso em que o
			// lote inteiro é recusado.
			writeError(w, errValidation("events["+strconv.Itoa(i)+"].client_id"))
			return
		}
		rejected[i] = syncResultDTO{
			ClientID: ev.ClientID, Status: string(domain.SyncStatusRejected),
			Code: "invalid_event", Field: field,
		}
	}

	applied, err := h.sessions.ApplyEvents(r.Context(), claims.TenantID, claims.Subject, events)
	if err != nil {
		h.logger.Error("sync_push_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := syncResponse{Results: make([]syncResultDTO, 0, len(req.Events)), ReceivedAt: time.Now().UTC()}
	next := 0
	for i := range req.Events {
		var item syncResultDTO
		if r, ok := rejected[i]; ok {
			item = r
		} else {
			res := applied[next]
			next++
			item = syncResultDTO{
				ClientID: res.ClientID, Status: string(res.Status),
				Code: res.Code, SessionID: res.SessionID,
			}
		}
		switch domain.SyncStatus(item.Status) {
		case domain.SyncStatusAccepted:
			resp.Accepted++
		case domain.SyncStatusDuplicate:
			resp.Duplicates++
		default:
			resp.Rejected++
		}
		resp.Results = append(resp.Results, item)
	}
	resp.State = h.stateDTO(r, claims.TenantID, claims.Subject)

	writeJSON(w, http.StatusOK, resp)
}

type pullResponse struct {
	// Plan vem inteiro quando mudou desde o cursor: o plano é pequeno e
	// substituir o cache local é mais simples (e mais seguro) que aplicar
	// diff de árvore no device.
	Plan       *planResponse      `json:"plan"`
	Exercises  []exerciseResponse `json:"exercises"`
	NextCursor string             `json:"next_cursor,omitempty"`
	HasMore    bool               `json:"has_more"`
	ServerTime time.Time          `json:"server_time"`
}

// pullCursor é o cursor opaco do pull incremental. Carrega **duas** marcas
// diferentes porque são dois fluxos com naturezas diferentes:
//
//   - Watermark: relógio do banco na última página completa. É contra ele que
//     o plano é comparado. Sem essa marca, o cursor da biblioteca (que só
//     avança quando a biblioteca muda) faria o servidor reenviar o plano
//     inteiro em toda sincronização, para sempre.
//   - ExUpdatedAt/ExID: keyset (updated_at, id) da última linha da biblioteca.
type pullCursor struct {
	Watermark   string `json:"w,omitempty"`
	ExUpdatedAt string `json:"u,omitempty"`
	ExID        string `json:"i,omitempty"`
}

func encodePullCursor(c pullCursor) string {
	raw, err := json.Marshal(c)
	if err != nil {
		// Struct de três strings: não há como falhar.
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

func decodePullCursor(raw string) (pullCursor, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return pullCursor{}, err
	}
	var c pullCursor
	if err := json.Unmarshal(decoded, &c); err != nil {
		return pullCursor{}, err
	}
	return c, nil
}

// parseCursorTime lê um carimbo do cursor. Vazio é sincronização inicial.
func parseCursorTime(v string) (time.Time, error) {
	if v == "" {
		return time.Time{}, nil
	}
	return time.Parse(time.RFC3339Nano, v)
}

// Pull é a leitura incremental do que mudou desde o cursor (ADR-003 §4):
// plano ativo e biblioteca.
//
// Cursor vazio significa primeira sincronização — vem tudo. A resposta **sempre**
// devolve `next_cursor`, inclusive na última página: é ele que o device guarda
// para a próxima vez, e um cursor que só aparecesse com `has_more` deixaria o
// cliente sem como avançar.
func (h *SyncHandler) Pull(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	ctx := r.Context()

	var cursor pullCursor
	if raw := strings.TrimSpace(r.URL.Query().Get("cursor")); raw != "" {
		parsed, err := decodePullCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		cursor = parsed
	}
	since, err := parseCursorTime(cursor.ExUpdatedAt)
	if err != nil {
		writeError(w, errInvalidCursor())
		return
	}
	watermark, err := parseCursorTime(cursor.Watermark)
	if err != nil {
		writeError(w, errInvalidCursor())
		return
	}
	if cursor.ExID != "" {
		if _, err := uuid.Parse(cursor.ExID); err != nil {
			writeError(w, errInvalidCursor())
			return
		}
	}

	limit := 0
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 || parsed > maxPullPageSize {
			writeError(w, errValidation("limit"))
			return
		}
		limit = parsed
	}
	locale := requestLocaleOrDefault(r)

	// O relógio da marca d'água é o do banco: `updated_at` é carimbado por
	// now() do Postgres, e comparar com o relógio do processo perderia
	// atualizações sempre que os dois divergissem.
	now, err := h.sessions.ServerTime(ctx)
	if err != nil {
		h.logger.Error("pull_clock_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	items, hasMore, err := h.exercises.ListUpdatedSince(ctx, claims.TenantID, since, cursor.ExID, locale, limit)
	if err != nil {
		h.logger.Error("pull_exercises_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := pullResponse{
		Exercises:  make([]exerciseResponse, 0, len(items)),
		HasMore:    hasMore,
		ServerTime: now,
	}
	for _, item := range items {
		resp.Exercises = append(resp.Exercises, exerciseToResponse(ctx, h.presigner, item.Exercise,
			item.DisplayName, item.Instructions, item.NameLocale))
	}

	next := pullCursor{ExUpdatedAt: cursor.ExUpdatedAt, ExID: cursor.ExID, Watermark: cursor.Watermark}
	if len(items) > 0 {
		last := items[len(items)-1]
		next.ExUpdatedAt, next.ExID = last.SortKey, last.ID
	}
	if !hasMore {
		// A marca d'água só avança quando a página fecha o delta: avançá-la no
		// meio da paginação esconderia o que mudou enquanto o device pagina.
		next.Watermark = now.Add(-pullWatermarkLag).Format(time.RFC3339Nano)
	}
	resp.NextCursor = encodePullCursor(next)

	plan, apiErr := h.changedPlan(r, claims.TenantID, claims.Subject, watermark, locale)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	resp.Plan = plan

	writeJSON(w, http.StatusOK, resp)
}

type overrideDayRequest struct {
	DayID string `json:"day_id"`
	// StudentID só é aceito de professor: o aluno troca o próprio dia, o
	// coach troca o do aluno dele.
	StudentID string `json:"student_id"`
}

// OverrideDay troca manualmente o próximo dia da rotação (ADR-004 §3) — o
// "trocar treino de hoje" da tela do aluno.
func (h *SyncHandler) OverrideDay(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req overrideDayRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	dayID := strings.TrimSpace(req.DayID)
	if _, err := uuid.Parse(dayID); err != nil {
		writeError(w, errValidation("day_id"))
		return
	}

	studentID := claims.Subject
	if raw := strings.TrimSpace(req.StudentID); raw != "" && raw != claims.Subject {
		if _, err := uuid.Parse(raw); err != nil {
			writeError(w, errValidation("student_id"))
			return
		}
		// A rota é /me/plan/…, mas o ADR-004 §3 dá o override ao aluno **ou**
		// ao professor; mexer no dia de outra pessoa exige ser professor.
		if !hasRole(claims, "coach") && !hasRole(claims, "owner") {
			writeError(w, errForbidden())
			return
		}
		studentID = raw
	}

	state, err := h.plans.SetNextDay(r.Context(), claims.TenantID, studentID, dayID)
	switch {
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errNotFound("plan"))
		return
	case errors.Is(err, repo.ErrDayNotInPlan):
		writeError(w, errDayNotInPlan(dayID))
		return
	case err != nil:
		h.logger.Error("override_day_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	writeJSON(w, http.StatusOK, h.stateFromDomain(r, claims.TenantID, state))
}

// changedPlan devolve o plano ativo do aluno quando algo nele mudou depois do
// cursor. Cursor vazio (`since` zero) é primeira sincronização: vem sempre.
func (h *SyncHandler) changedPlan(r *http.Request, tenantID, studentID string, since time.Time, locale domain.Locale) (*planResponse, *APIError) {
	ctx := r.Context()
	state, err := h.plans.GetState(ctx, tenantID, studentID)
	if errors.Is(err, repo.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		h.logger.Error("pull_state_failed", slog.Any("error", err))
		apiErr := errInternal()
		return nil, &apiErr
	}
	plan, err := h.plans.GetPlan(ctx, tenantID, state.PlanID)
	if err != nil {
		h.logger.Error("pull_plan_failed", slog.Any("error", err))
		apiErr := errInternal()
		return nil, &apiErr
	}
	version, err := h.plans.GetVersionByID(ctx, tenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("pull_version_failed", slog.Any("error", err))
		apiErr := errInternal()
		return nil, &apiErr
	}

	changed := since.IsZero() ||
		plan.UpdatedAt.After(since) ||
		state.UpdatedAt.After(since) ||
		(version.PublishedAt != nil && version.PublishedAt.After(since))
	if !changed {
		return nil, nil
	}

	resp, apiErr := h.buildResponse(ctx, tenantID, plan, &version, locale)
	if apiErr != nil {
		return nil, apiErr
	}
	return &resp, nil
}

// stateDTO lê a rotação depois de aplicar o lote. Falha aqui não derruba o
// push: os eventos já foram gravados, e o app pega o estado no próximo
// /me/today.
func (h *SyncHandler) stateDTO(r *http.Request, tenantID, studentID string) *syncStateDTO {
	state, err := h.plans.GetState(r.Context(), tenantID, studentID)
	if err != nil {
		if !errors.Is(err, repo.ErrNotFound) {
			h.logger.Error("sync_state_failed", slog.Any("error", err))
		}
		return nil
	}
	return h.stateFromDomain(r, tenantID, state)
}

// stateFromDomain serializa a rotação já com o rótulo do próximo dia — a UI
// mostra "próximo treino: B" sem ter de procurar o dia na árvore.
func (h *SyncHandler) stateFromDomain(r *http.Request, tenantID string, state domain.StudentPlanState) *syncStateDTO {
	dto := &syncStateDTO{
		PlanID: state.PlanID, ActiveVersionID: state.ActiveVersionID,
		LastSessionAt: state.LastSessionAt,
	}
	if state.NextDayID == nil {
		return dto
	}
	dto.NextDayID = *state.NextDayID

	days, err := h.plans.GetVersionTree(r.Context(), tenantID, state.ActiveVersionID)
	if err != nil {
		h.logger.Error("sync_state_tree_failed", slog.Any("error", err))
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

// parseSyncEvent valida um evento da fila. Devolve o campo problemático em vez
// de um erro: campo vazio significa evento válido.
func parseSyncEvent(raw syncEventDTO) (domain.SyncEvent, string) {
	ev := domain.SyncEvent{
		ClientID:    strings.TrimSpace(raw.ClientID),
		Type:        domain.SyncEventType(strings.TrimSpace(raw.Type)),
		PerformedAt: raw.PerformedAt,
	}
	if _, err := uuid.Parse(ev.ClientID); err != nil {
		return ev, "client_id"
	}
	if !domain.IsValidSyncEventType(ev.Type) {
		return ev, "type"
	}
	if ev.PerformedAt.IsZero() || ev.PerformedAt.After(time.Now().Add(maxClockSkew)) {
		return ev, "performed_at"
	}

	var p syncPayloadDTO
	if len(raw.Payload) > 0 {
		if err := json.Unmarshal(raw.Payload, &p); err != nil {
			return ev, "payload"
		}
	}

	switch ev.Type {
	case domain.SyncEventSessionStart:
		ev.DayID = strings.TrimSpace(p.DayID)
		if _, err := uuid.Parse(ev.DayID); err != nil {
			return ev, "payload.day_id"
		}
	case domain.SyncEventSessionFinish:
		ev.SessionClientID = strings.TrimSpace(p.SessionClientID)
		if _, err := uuid.Parse(ev.SessionClientID); err != nil {
			return ev, "payload.session_client_id"
		}
	case domain.SyncEventSetLog, domain.SyncEventSetRevision:
		ev.SessionClientID = strings.TrimSpace(p.SessionClientID)
		if _, err := uuid.Parse(ev.SessionClientID); err != nil {
			return ev, "payload.session_client_id"
		}
		ev.ExerciseID = strings.TrimSpace(p.ExerciseID)
		if _, err := uuid.Parse(ev.ExerciseID); err != nil {
			return ev, "payload.exercise_id"
		}
		ev.SetNo = p.SetNo
		if ev.SetNo <= 0 || ev.SetNo > maxSetsPerExercise {
			return ev, "payload.set_no"
		}
		if p.RepsDone != nil && (*p.RepsDone < 0 || *p.RepsDone > maxReps) {
			return ev, "payload.reps_done"
		}
		if p.LoadKg != nil && (*p.LoadKg < 0 || *p.LoadKg > maxTargetValue) {
			return ev, "payload.load_kg"
		}
		if p.RPE != nil && (*p.RPE < 0 || *p.RPE > 10) {
			return ev, "payload.rpe"
		}
		ev.RepsDone, ev.LoadKg, ev.RPE = p.RepsDone, p.LoadKg, p.RPE
		if ev.Type == domain.SyncEventSetRevision {
			ev.Revises = strings.TrimSpace(p.Revises)
			if _, err := uuid.Parse(ev.Revises); err != nil {
				return ev, "payload.revises"
			}
		}
	}
	return ev, ""
}

// exerciseIDsOf lista, na ordem do treino, os exercícios de um dia — sem
// repetir quem aparece duas vezes.
func exerciseIDsOf(day domain.Day) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, 8)
	for _, b := range day.Blocks {
		for _, be := range b.Exercises {
			if _, dup := seen[be.ExerciseID]; dup {
				continue
			}
			seen[be.ExerciseID] = struct{}{}
			out = append(out, be.ExerciseID)
		}
	}
	return out
}
