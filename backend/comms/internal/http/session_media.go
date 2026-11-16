package http

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/duo/comms/internal/domain"
	"github.com/marcus-coube/duo/comms/internal/media"
	"github.com/marcus-coube/duo/comms/internal/push"
	"github.com/marcus-coube/duo/comms/internal/repo"
)

// PurposeProgressPhotos é a finalidade de consentimento que a mídia de
// execução exige (ADR-020 §5, ADR-008 §1) — imagem do corpo do aluno.
const PurposeProgressPhotos = "progress_photos"

const (
	maxSessionMediaNoteLen     = 280
	maxSessionMediaFeedbackLen = 1000
	maxExerciseNameLen         = 200
)

// SessionMediaStore é o que o handler usa do storage (satisfeito por
// *media.Presigner; os testes injetam um fake em memória).
type SessionMediaStore interface {
	PresignSessionMediaPut(ctx context.Context, key, contentType string, sizeBytes int64) (string, time.Time, error)
	Head(ctx context.Context, key string) (media.ObjectInfo, error)
	SignedReadURL(ctx context.Context, key string) (string, error)
	DeleteObject(ctx context.Context, key string) error
}

// SessionMediaHandler expõe a mídia de execução (ADR-020, P12.1): o aluno
// anexa vídeo/foto ao treino, o professor dá ciência (e pode responder pelo
// chat) e a mídia expira — o job está em internal/job.
type SessionMediaHandler struct {
	logger        *slog.Logger
	media         *repo.SessionMediaRepo
	store         SessionMediaStore
	linker        StudentLinker
	conversations *repo.ConversationRepo
	chat          *ConversationHandler
	notifier      *push.Notifier
	now           func() time.Time
}

// NewSessionMediaHandler cria o handler. notifier pode ser nil nos testes que
// não exercitam push.
func NewSessionMediaHandler(logger *slog.Logger, mediaRepo *repo.SessionMediaRepo, store SessionMediaStore, linker StudentLinker,
	conversations *repo.ConversationRepo, chat *ConversationHandler, notifier *push.Notifier) *SessionMediaHandler {
	return &SessionMediaHandler{
		logger: logger, media: mediaRepo, store: store, linker: linker,
		conversations: conversations, chat: chat, notifier: notifier, now: time.Now,
	}
}

// WithClock troca o relógio do handler (instante da ciência) — só para teste.
func (h *SessionMediaHandler) WithClock(now func() time.Time) *SessionMediaHandler {
	h.now = now
	return h
}

type sessionMediaDTO struct {
	ID              string     `json:"id"`
	StudentID       string     `json:"student_id"`
	SessionClientID string     `json:"session_client_id"`
	ExerciseID      string     `json:"exercise_id,omitempty"`
	ExerciseName    string     `json:"exercise_name,omitempty"`
	ContentType     string     `json:"content_type"`
	SizeBytes       int64      `json:"size_bytes"`
	Note            string     `json:"note,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	AckedBy         string     `json:"acked_by,omitempty"`
	AckedAt         *time.Time `json:"acked_at,omitempty"`
	DeleteAfter     time.Time  `json:"delete_after"`
	DeletedAt       *time.Time `json:"deleted_at,omitempty"`
	// MediaURL é um GET assinado de 15 min; some quando a mídia expirou.
	MediaURL string `json:"media_url,omitempty"`
}

type sessionMediaListResponse struct {
	Items      []sessionMediaDTO `json:"items"`
	NextCursor string            `json:"next_cursor,omitempty"`
}

func (h *SessionMediaHandler) toDTO(ctx context.Context, m domain.SessionMedia) sessionMediaDTO {
	dto := sessionMediaDTO{
		ID: m.ID, StudentID: m.StudentID, SessionClientID: m.SessionClientID,
		ExerciseID: m.ExerciseID, ExerciseName: m.ExerciseName, ContentType: m.ContentType,
		SizeBytes: m.SizeBytes, Note: m.Note, CreatedAt: m.CreatedAt, AckedBy: m.AckedBy,
		AckedAt: m.AckedAt, DeleteAfter: m.DeleteAfter, DeletedAt: m.DeletedAt,
	}
	if m.MediaKey != "" && m.DeletedAt == nil {
		url, err := h.store.SignedReadURL(ctx, m.MediaKey)
		if err != nil {
			h.logger.Error("session_media_read_url_failed", slog.Any("error", err))
		}
		dto.MediaURL = url
	}
	return dto
}

// requireOwnConsent barra com 403 `consent_required` quando o aluno não tem a
// finalidade `progress_photos` nas claims (D6).
func requireOwnConsent(w http.ResponseWriter, claimsHas bool) bool {
	if !claimsHas {
		writeError(w, errConsentRequired(PurposeProgressPhotos))
		return false
	}
	return true
}

// Presign — POST /v1/me/session-media/presign.
func (h *SessionMediaHandler) Presign(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	if !requireOwnConsent(w, claims.HasConsent(PurposeProgressPhotos)) {
		return
	}
	var req struct {
		SessionClientID string `json:"session_client_id"`
		ContentType     string `json:"content_type"`
		SizeBytes       int64  `json:"size_bytes"`
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
	ext, ok := media.LookupSessionMediaType(req.ContentType)
	if !ok {
		writeError(w, errMediaTypeNotAllowed(req.ContentType))
		return
	}
	if req.SizeBytes <= 0 {
		writeError(w, errValidation("size_bytes"))
		return
	}
	if req.SizeBytes > media.MaxSessionMediaBytes {
		writeError(w, errMediaTooLarge(media.MaxSessionMediaBytes))
		return
	}

	key, err := media.SessionMediaKey(claims.TenantID, claims.Subject, sessionClientID, ext)
	if err != nil {
		h.logger.Error("session_media_key_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	uploadURL, expiresAt, err := h.store.PresignSessionMediaPut(r.Context(), key, req.ContentType, req.SizeBytes)
	if err != nil {
		h.logger.Error("session_media_presign_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, presignResponse{
		UploadURL: uploadURL,
		Method:    http.MethodPut,
		Headers: map[string]string{
			"Content-Type":   req.ContentType,
			"Content-Length": strconv.FormatInt(req.SizeBytes, 10),
		},
		Key:       key,
		ExpiresAt: expiresAt,
	})
}

// Create — POST /v1/me/session-media: registra a mídia depois do upload.
func (h *SessionMediaHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	if !requireOwnConsent(w, claims.HasConsent(PurposeProgressPhotos)) {
		return
	}
	var req struct {
		SessionClientID string `json:"session_client_id"`
		MediaKey        string `json:"media_key"`
		ExerciseID      string `json:"exercise_id"`
		ExerciseName    string `json:"exercise_name"`
		Note            string `json:"note"`
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
	exerciseID := strings.TrimSpace(req.ExerciseID)
	if exerciseID != "" {
		if _, err := uuid.Parse(exerciseID); err != nil {
			writeError(w, errValidation("exercise_id"))
			return
		}
	}
	exerciseName := strings.TrimSpace(req.ExerciseName)
	if utf8.RuneCountInString(exerciseName) > maxExerciseNameLen {
		writeError(w, errValidation("exercise_name"))
		return
	}
	note := strings.TrimSpace(req.Note)
	if utf8.RuneCountInString(note) > maxSessionMediaNoteLen {
		writeError(w, errValidation("note"))
		return
	}
	// Par de segurança do presign: só a pasta da sessão do próprio aluno.
	if !media.ValidSessionMediaKey(req.MediaKey, claims.TenantID, claims.Subject, sessionClientID) {
		writeError(w, errInvalidMediaKey())
		return
	}

	// O que vale é o objeto no storage, não o que o cliente declarou.
	info, err := h.store.Head(r.Context(), req.MediaKey)
	if errors.Is(err, media.ErrObjectNotFound) {
		writeError(w, errMediaNotUploaded())
		return
	}
	if err != nil {
		h.logger.Error("session_media_head_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	contentType := strings.ToLower(strings.TrimSpace(strings.SplitN(info.ContentType, ";", 2)[0]))
	if _, ok := media.LookupSessionMediaType(contentType); !ok {
		h.discard(r.Context(), req.MediaKey)
		writeError(w, errMediaTypeNotAllowed(contentType))
		return
	}
	if info.SizeBytes <= 0 || info.SizeBytes > media.MaxSessionMediaBytes {
		h.discard(r.Context(), req.MediaKey)
		writeError(w, errMediaTooLarge(media.MaxSessionMediaBytes))
		return
	}

	created, isNew, err := h.media.Create(r.Context(), domain.SessionMedia{
		TenantID: claims.TenantID, StudentID: claims.Subject, SessionClientID: sessionClientID,
		ExerciseID: exerciseID, ExerciseName: exerciseName, MediaKey: req.MediaKey,
		ContentType: contentType, SizeBytes: info.SizeBytes, Note: note,
	})
	if errors.Is(err, repo.ErrSessionMediaLimit) {
		h.discard(r.Context(), req.MediaKey)
		writeError(w, errSessionMediaLimit(repo.MaxSessionMediaPerSession))
		return
	}
	if err != nil {
		h.logger.Error("session_media_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if isNew {
		h.notifyCoach(r.Context(), created)
	}
	writeJSON(w, http.StatusCreated, h.toDTO(r.Context(), created))
}

// discard apaga um objeto recusado no registro; falha só é logada (o objeto
// fica na pasta do aluno, que a exclusão de conta limpa).
func (h *SessionMediaHandler) discard(ctx context.Context, key string) {
	if err := h.store.DeleteObject(ctx, key); err != nil {
		h.logger.Error("session_media_discard_failed", slog.Any("error", err))
	}
}

// notifyCoach manda push ao professor vinculado: mídia nova a avaliar. Aluno
// sem vínculo ou falha do identity/push não derrubam o registro, que já está
// gravado.
func (h *SessionMediaHandler) notifyCoach(ctx context.Context, m domain.SessionMedia) {
	if h.notifier == nil {
		return
	}
	coachID, found, err := h.linker.CoachOf(ctx, m.TenantID, m.StudentID)
	if err != nil {
		h.logger.Error("session_media_lookup_coach_failed", slog.Any("error", err))
		return
	}
	if !found {
		return
	}
	h.notifier.Send(ctx, m.TenantID, coachID, push.KindSessionMedia, map[string]string{
		"type": "session_media.new", "student_id": m.StudentID, "media_id": m.ID, "tab": "checkins",
	})
}

// ListMine — GET /v1/me/session-media?session_client_id=.
func (h *SessionMediaHandler) ListMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	sessionClientID := strings.TrimSpace(r.URL.Query().Get("session_client_id"))
	if _, err := uuid.Parse(sessionClientID); err != nil {
		writeError(w, errValidation("session_client_id"))
		return
	}
	items, err := h.media.ListForSession(r.Context(), claims.TenantID, claims.Subject, sessionClientID)
	if err != nil {
		h.logger.Error("session_media_list_mine_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := sessionMediaListResponse{Items: make([]sessionMediaDTO, 0, len(items))}
	for _, m := range items {
		resp.Items = append(resp.Items, h.toDTO(r.Context(), m))
	}
	writeJSON(w, http.StatusOK, resp)
}

// DeleteMine — DELETE /v1/me/session-media/{id}: o aluno retira a mídia; o
// objeto é apagado na hora e a linha some.
func (h *SessionMediaHandler) DeleteMine(w http.ResponseWriter, r *http.Request) {
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
	m, err := h.media.Get(r.Context(), claims.TenantID, id)
	if errors.Is(err, repo.ErrNotFound) || (err == nil && m.StudentID != claims.Subject) {
		writeError(w, errNotFound("session_media"))
		return
	}
	if err != nil {
		h.logger.Error("session_media_load_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	// Objeto primeiro: se o storage falhar a linha fica e a retirada pode ser
	// repetida; apagar a linha antes deixaria um objeto órfão sem dono.
	if err := h.store.DeleteObject(r.Context(), m.MediaKey); err != nil {
		h.logger.Error("session_media_delete_object_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if _, err := h.media.Delete(r.Context(), claims.TenantID, claims.Subject, id); err != nil {
		h.logger.Error("session_media_delete_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// List — GET /v1/session-media?student_id=&pending=: a mídia dos alunos do
// coach (o owner vê o tenant). `pending=true` = só a sem ciência.
func (h *SessionMediaHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	q := r.URL.Query()
	filter := repo.SessionMediaFilter{PendingOnly: q.Get("pending") == "true"}
	if raw := strings.TrimSpace(q.Get("student_id")); raw != "" {
		if _, err := uuid.Parse(raw); err != nil {
			writeError(w, errValidation("student_id"))
			return
		}
		filter.StudentID = raw
	}
	cursorAt, cursorID, limit, apiErr := parseListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	switch {
	case filter.StudentID != "":
		if apiErr := checkStudentLink(r.Context(), h.logger, h.linker, claims, filter.StudentID); apiErr != nil {
			writeError(w, *apiErr)
			return
		}
	case isOwner(claims):
		// tenant inteiro
	default:
		students, err := h.linker.StudentsOf(r.Context(), claims.TenantID, claims.Subject)
		if err != nil {
			h.logger.Error("coach_link_check_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		filter.StudentIDs = make([]string, 0, len(students))
		for id := range students {
			filter.StudentIDs = append(filter.StudentIDs, id)
		}
	}

	items, hasMore, err := h.media.List(r.Context(), claims.TenantID, filter, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("session_media_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := sessionMediaListResponse{Items: make([]sessionMediaDTO, 0, len(items))}
	for _, m := range items {
		resp.Items = append(resp.Items, h.toDTO(r.Context(), m))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.CreatedAt, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// Ack — POST /v1/session-media/{id}/ack {feedback?}: a ciência do professor,
// uma vez (repetir não renova o prazo). Com `feedback`, vira mensagem de texto
// no chat direto com o aluno (ADR-020 §4), pelo mesmo caminho do chat (WS e
// push). Se a mensagem falhar depois da ciência, responde 500 e o professor
// pode repetir: a ciência é idempotente e a mensagem ainda não saiu.
func (h *SessionMediaHandler) Ack(w http.ResponseWriter, r *http.Request) {
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

	var req struct {
		Feedback string `json:"feedback"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		writeError(w, errInvalidBody())
		return
	}
	feedback := strings.TrimSpace(req.Feedback)
	if utf8.RuneCountInString(feedback) > maxSessionMediaFeedbackLen {
		writeError(w, errValidation("feedback"))
		return
	}

	existing, err := h.media.Get(r.Context(), claims.TenantID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("session_media"))
		return
	}
	if err != nil {
		h.logger.Error("session_media_load_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if apiErr := checkStudentLink(r.Context(), h.logger, h.linker, claims, existing.StudentID); apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	acked, err := h.media.Ack(r.Context(), claims.TenantID, id, claims.Subject, h.now().UTC())
	if err != nil {
		h.logger.Error("session_media_ack_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if feedback != "" && h.chat != nil {
		conv, err := h.conversations.GetOrCreate(r.Context(), claims.TenantID, acked.StudentID, claims.Subject)
		if err == nil {
			_, err = h.chat.PostText(r.Context(), conv, claims.Subject, feedbackBody(acked, feedback))
		}
		if err != nil {
			h.logger.Error("session_media_feedback_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
	}
	writeJSON(w, http.StatusOK, h.toDTO(r.Context(), acked))
}

// feedbackBody cita o treino (data) e o exercício antes do texto do professor:
// quem lê a resposta depois que a mídia expirou ainda sabe do que se trata. O
// cabeçalho é neutro quanto ao idioma (data ISO e nome do exercício).
func feedbackBody(m domain.SessionMedia, feedback string) string {
	ref := m.CreatedAt.UTC().Format("2006-01-02")
	if m.ExerciseName != "" {
		ref = m.ExerciseName + " · " + ref
	}
	return "[" + ref + "] " + feedback
}
