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
	"github.com/redis/go-redis/v9"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
	"github.com/marcus-coube/lyfta/comms/internal/push"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// maxCheckinNoteLen é o teto de `pain_notes`/`comment` — mesmo critério do
// maxNotesLen do workout/assessment (teto de payload, não regra de negócio).
const maxCheckinNoteLen = 500

// CheckinHandler expõe a avaliação estruturada de treino (P3.3): o aluno
// registra ao concluir a sessão, o coach revisa a fila (não revisados
// primeiro, Aceite do P3.3).
type CheckinHandler struct {
	logger      *slog.Logger
	checkins    *repo.CheckinRepo
	linker      StudentLinker
	redisClient *redis.Client
	notifier    *push.Notifier
}

// NewCheckinHandler cria o handler de check-ins.
//
// linker serve à fila do coach (só os alunos dele) e ao push da dor forte, que
// vai só para o coach atual do aluno (ADR-016 §6) — o identity é o dono do
// vínculo. notifier pode ser nil nos testes que não exercitam push (mesmo
// critério do ConversationHandler).
func NewCheckinHandler(logger *slog.Logger, checkins *repo.CheckinRepo, linker StudentLinker, redisClient *redis.Client, notifier *push.Notifier) *CheckinHandler {
	return &CheckinHandler{logger: logger, checkins: checkins, linker: linker, redisClient: redisClient, notifier: notifier}
}

type checkinDTO struct {
	ID              string     `json:"id"`
	StudentID       string     `json:"student_id"`
	SessionClientID string     `json:"session_client_id"`
	Rating          int        `json:"rating"`
	Difficulty      int        `json:"difficulty"`
	Pain            string     `json:"pain"`
	PainNotes       string     `json:"pain_notes,omitempty"`
	Comment         string     `json:"comment,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	ReviewedBy      string     `json:"reviewed_by,omitempty"`
	ReviewedAt      *time.Time `json:"reviewed_at,omitempty"`
}

type checkinListResponse struct {
	Items      []checkinDTO `json:"items"`
	NextCursor string       `json:"next_cursor,omitempty"`
}

// checkinPainEvent é o evento publicado no canal comms:user:{coach} quando a
// dor relatada é `strong` — mesmo envelope (campo `type`) dos eventos de
// chat (P3.2), consumido hoje só pelo WS (o coach vê a notificação se
// estiver com o app aberto); a P3.4 decide o que fazer quando ele não está.
type checkinPainEvent struct {
	Type      string `json:"type"`
	CheckinID string `json:"checkin_id"`
	StudentID string `json:"student_id"`
	Pain      string `json:"pain"`
}

// Create grava o check-in do aluno autenticado — student_id vem sempre da
// claim, nunca do corpo da requisição (o aluno só pode avaliar o próprio
// treino).
func (h *CheckinHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req struct {
		SessionClientID string `json:"session_client_id"`
		Rating          int    `json:"rating"`
		Difficulty      int    `json:"difficulty"`
		Pain            string `json:"pain"`
		PainNotes       string `json:"pain_notes"`
		Comment         string `json:"comment"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	sessionClientID := strings.TrimSpace(req.SessionClientID)
	if _, err := uuid.Parse(sessionClientID); err != nil {
		writeError(w, errValidation("session_client_id"))
		return
	}
	if !domain.IsValidCheckinScore(req.Rating) {
		writeError(w, errValidation("rating"))
		return
	}
	if !domain.IsValidCheckinScore(req.Difficulty) {
		writeError(w, errValidation("difficulty"))
		return
	}
	pain := domain.PainLevel(strings.TrimSpace(req.Pain))
	if pain == "" {
		pain = domain.PainNone
	}
	if !domain.IsValidPainLevel(pain) {
		writeError(w, errValidation("pain"))
		return
	}
	painNotes := strings.TrimSpace(req.PainNotes)
	comment := strings.TrimSpace(req.Comment)
	if len(painNotes) > maxCheckinNoteLen {
		writeError(w, errValidation("pain_notes"))
		return
	}
	if len(comment) > maxCheckinNoteLen {
		writeError(w, errValidation("comment"))
		return
	}

	created, err := h.checkins.Create(r.Context(), domain.WorkoutCheckin{
		TenantID: claims.TenantID, StudentID: claims.Subject, SessionClientID: sessionClientID,
		Rating: req.Rating, Difficulty: req.Difficulty, Pain: pain, PainNotes: painNotes, Comment: comment,
	})
	if err != nil {
		h.logger.Error("checkin_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if created.Pain == domain.PainStrong {
		h.notifyCoachOfStrongPain(r, created)
	}

	writeJSON(w, http.StatusCreated, h.toDTO(created))
}

// notifyCoachOfStrongPain publica o evento de dor forte para o coach atual do
// aluno (consultado no identity, ADR-016 §6) e manda push pra ele — sempre,
// esteja online ou não (ao contrário de message.new, dor é importante o bastante
// pra tocar mesmo com o app aberto). Aluno sem vínculo ou falha ao consultar o
// identity/publicar/mandar push não derrubam a criação do check-in, que já
// está gravado.
func (h *CheckinHandler) notifyCoachOfStrongPain(r *http.Request, c domain.WorkoutCheckin) {
	coachID, found, err := h.linker.CoachOf(r.Context(), c.TenantID, c.StudentID)
	if err != nil {
		h.logger.Error("checkin_pain_lookup_coach_failed", slog.Any("error", err))
		return
	}
	if !found {
		return
	}
	payload, err := json.Marshal(checkinPainEvent{
		Type: "checkin.pain_strong", CheckinID: c.ID, StudentID: c.StudentID, Pain: string(c.Pain),
	})
	if err != nil {
		h.logger.Error("checkin_pain_event_marshal_failed", slog.Any("error", err))
		return
	}
	if err := pubsub.PublishToUser(r.Context(), h.redisClient, coachID, payload); err != nil {
		h.logger.Error("checkin_pain_event_publish_failed", slog.Any("error", err), slog.String("coach_id", coachID))
	}
	if h.notifier != nil {
		h.notifier.Send(r.Context(), c.TenantID, coachID, push.KindCheckinPainStrong, map[string]string{
			"type": "checkin.pain_strong", "checkin_id": c.ID, "student_id": c.StudentID,
		})
	}
}

// List devolve os check-ins do tenant (todos, ou só de um aluno com
// `?student_id=`), coach/owner apenas — ordenados com os não revisados
// primeiro (Aceite do P3.3).
func (h *CheckinHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	studentID, cursor, limit, apiErr := parseCheckinListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	var (
		items   []domain.WorkoutCheckin
		hasMore bool
		err     error
	)
	switch {
	case studentID != "":
		// Fila de um aluno: o vínculo é checado (owner passa).
		if apiErr := checkStudentLink(r.Context(), h.logger, h.linker, claims, studentID); apiErr != nil {
			writeError(w, *apiErr)
			return
		}
		items, hasMore, err = h.checkins.List(r.Context(), claims.TenantID, studentID, cursor, limit)
	case isOwner(claims):
		items, hasMore, err = h.checkins.List(r.Context(), claims.TenantID, "", cursor, limit)
	default:
		// Coach sem owner: só a fila dos alunos dele (ADR-016 §6).
		students, linkErr := h.linker.StudentsOf(r.Context(), claims.TenantID, claims.Subject)
		if linkErr != nil {
			h.logger.Error("coach_link_check_failed", slog.Any("error", linkErr))
			writeError(w, errInternal())
			return
		}
		ids := make([]string, 0, len(students))
		for id := range students {
			ids = append(ids, id)
		}
		items, hasMore, err = h.checkins.ListForStudents(r.Context(), claims.TenantID, ids, cursor, limit)
	}
	if err != nil {
		h.logger.Error("checkin_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := checkinListResponse{Items: make([]checkinDTO, 0, len(items))}
	for _, c := range items {
		resp.Items = append(resp.Items, h.toDTO(c))
	}
	if hasMore && len(items) > 0 {
		next := repo.NewCheckinCursor(items[len(items)-1])
		resp.NextCursor = encodeCheckinCursor(next.ReviewedAt, next.CreatedAt, next.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// Stats — GET /v1/checkins/stats (P8.1): quantos check-ins esperam revisão.
// Coach conta só os alunos dele; owner conta o tenant inteiro, com
// `?coach_id=` opcional para filtrar por professor.
func (h *CheckinHandler) Stats(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	coachID := claims.Subject
	if isOwner(claims) {
		coachID = ""
		if raw := r.URL.Query().Get("coach_id"); raw != "" {
			if _, err := uuid.Parse(raw); err != nil {
				writeError(w, errValidation("coach_id"))
				return
			}
			coachID = raw
		}
	}
	var ids []string // nil = tenant inteiro
	if coachID != "" {
		students, err := h.linker.StudentsOf(r.Context(), claims.TenantID, coachID)
		if err != nil {
			h.logger.Error("coach_link_check_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		ids = make([]string, 0, len(students))
		for id := range students {
			ids = append(ids, id)
		}
	}
	n, err := h.checkins.CountUnreviewed(r.Context(), claims.TenantID, ids)
	if err != nil {
		h.logger.Error("checkin_stats_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"unreviewed": n})
}

// Review marca um check-in como visto pelo coach autenticado — idempotente
// (segunda chamada não troca quem revisou primeiro).
func (h *CheckinHandler) Review(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("id"))
		return
	}

	// Carrega o check-in antes para checar o vínculo com o aluno dele: check-in
	// inexistente e de aluno que não é do coach respondem diferente só no
	// código (not_found × student_not_found), nenhum dos dois vaza dado.
	existing, err := h.checkins.Get(r.Context(), claims.TenantID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("checkin"))
		return
	}
	if err != nil {
		h.logger.Error("checkin_load_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if apiErr := checkStudentLink(r.Context(), h.logger, h.linker, claims, existing.StudentID); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	reviewed, err := h.checkins.Review(r.Context(), claims.TenantID, id, claims.Subject)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("checkin"))
		return
	}
	if err != nil {
		h.logger.Error("checkin_review_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, h.toDTO(reviewed))
}

func (h *CheckinHandler) toDTO(c domain.WorkoutCheckin) checkinDTO {
	return checkinDTO{
		ID: c.ID, StudentID: c.StudentID, SessionClientID: c.SessionClientID,
		Rating: c.Rating, Difficulty: c.Difficulty, Pain: string(c.Pain),
		PainNotes: c.PainNotes, Comment: c.Comment, CreatedAt: c.CreatedAt,
		ReviewedBy: c.ReviewedBy, ReviewedAt: c.ReviewedAt,
	}
}
