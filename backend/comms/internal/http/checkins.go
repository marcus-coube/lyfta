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
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// maxCheckinNoteLen é o teto de `pain_notes`/`comment` — mesmo critério do
// maxNotesLen do workout/assessment (teto de payload, não regra de negócio).
const maxCheckinNoteLen = 500

// CheckinHandler expõe a avaliação estruturada de treino (P3.3): o aluno
// registra ao concluir a sessão, o coach revisa a fila (não revisados
// primeiro, Aceite do P3.3).
type CheckinHandler struct {
	logger        *slog.Logger
	checkins      *repo.CheckinRepo
	conversations *repo.ConversationRepo
	redisClient   *redis.Client
}

// NewCheckinHandler cria o handler de check-ins.
//
// conversations entra só para o gancho de push da dor forte (ver Create):
// como o comms já modela o par aluno-coach em `conversations` (P3.2), reusar
// essa tabela para descobrir "o coach deste aluno" é mais barato que
// inventar uma consulta M2M nova ao identity — que é o único lugar que sabe
// o vínculo coach↔aluno de verdade (dívida aberta desde o P1.4). Se o aluno
// ainda não tem conversa aberta com nenhum coach, nada é publicado: o
// alcance completo ("qualquer professor do tenant" via FCM) é escopo da
// P3.4.
func NewCheckinHandler(logger *slog.Logger, checkins *repo.CheckinRepo, conversations *repo.ConversationRepo, redisClient *redis.Client) *CheckinHandler {
	return &CheckinHandler{logger: logger, checkins: checkins, conversations: conversations, redisClient: redisClient}
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
		h.notifyCoachesOfStrongPain(r, created)
	}

	writeJSON(w, http.StatusCreated, h.toDTO(created))
}

// notifyCoachesOfStrongPain publica o evento de dor forte para cada coach
// com quem o aluno já tem conversa aberta neste tenant — falha ao publicar
// não derruba a criação do check-in, que já está gravado.
func (h *CheckinHandler) notifyCoachesOfStrongPain(r *http.Request, c domain.WorkoutCheckin) {
	convs, err := h.conversations.ListForUser(r.Context(), c.TenantID, c.StudentID)
	if err != nil {
		h.logger.Error("checkin_pain_lookup_coaches_failed", slog.Any("error", err))
		return
	}
	payload, err := json.Marshal(checkinPainEvent{
		Type: "checkin.pain_strong", CheckinID: c.ID, StudentID: c.StudentID, Pain: string(c.Pain),
	})
	if err != nil {
		h.logger.Error("checkin_pain_event_marshal_failed", slog.Any("error", err))
		return
	}
	for _, conv := range convs {
		if err := pubsub.PublishToUser(r.Context(), h.redisClient, conv.CoachID, payload); err != nil {
			h.logger.Error("checkin_pain_event_publish_failed", slog.Any("error", err), slog.String("coach_id", conv.CoachID))
		}
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

	items, hasMore, err := h.checkins.List(r.Context(), claims.TenantID, studentID, cursor, limit)
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
