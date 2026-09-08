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
	"github.com/marcus-coube/lyfta/comms/internal/media"
	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// maxMessageBodyLen é o teto de texto por mensagem — teto de payload, não
// regra de negócio (mesmo critério do maxNotesLen do assessment/workout).
const maxMessageBodyLen = 4000

// ConversationHandler expõe o chat (P3.2): lista de conversas com prévia e
// não lidas, histórico paginado, envio de mensagem (texto|imagem) e leitura
// em lote. WS é entrega quente — este handler é a verdade (banco) e quem
// publica os eventos que o WS retransmite (internal/pubsub + internal/ws).
type ConversationHandler struct {
	logger        *slog.Logger
	conversations *repo.ConversationRepo
	messages      *repo.MessageRepo
	presigner     *media.Presigner
	redisClient   *redis.Client
}

// NewConversationHandler cria o handler de conversas.
func NewConversationHandler(logger *slog.Logger, conversations *repo.ConversationRepo, messages *repo.MessageRepo, presigner *media.Presigner, redisClient *redis.Client) *ConversationHandler {
	return &ConversationHandler{
		logger: logger, conversations: conversations, messages: messages,
		presigner: presigner, redisClient: redisClient,
	}
}

type conversationDTO struct {
	ID            string      `json:"id"`
	StudentID     string      `json:"student_id"`
	CoachID       string      `json:"coach_id"`
	CreatedAt     time.Time   `json:"created_at"`
	LastMessageAt *time.Time  `json:"last_message_at,omitempty"`
	LastMessage   *messageDTO `json:"last_message,omitempty"`
	UnreadCount   int         `json:"unread_count"`
}

type conversationListResponse struct {
	Items []conversationDTO `json:"items"`
}

type messageDTO struct {
	ID             string     `json:"id"`
	ConversationID string     `json:"conversation_id"`
	SenderID       string     `json:"sender_id"`
	Type           string     `json:"type"`
	Body           string     `json:"body,omitempty"`
	MediaURL       string     `json:"media_url,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	ReadAt         *time.Time `json:"read_at,omitempty"`
}

type messageListResponse struct {
	Items      []messageDTO `json:"items"`
	NextCursor string       `json:"next_cursor,omitempty"`
}

// wsEvent é o payload publicado no Redis e retransmitido pelo WS
// (internal/ws + internal/pubsub) — mesmo envelope para `message.new` e
// `message.read`, campos não usados por um tipo ficam de fora pelo omitempty.
type wsEvent struct {
	Type           string      `json:"type"`
	ConversationID string      `json:"conversation_id"`
	Message        *messageDTO `json:"message,omitempty"`
	ReaderID       string      `json:"reader_id,omitempty"`
	MessageIDs     []string    `json:"message_ids,omitempty"`
	ReadAt         *time.Time  `json:"read_at,omitempty"`
}

// List devolve as conversas do usuário autenticado — coach vê as suas (uma
// por aluno), aluno vê a sua.
func (h *ConversationHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	items, err := h.conversations.ListForUser(r.Context(), claims.TenantID, claims.Subject)
	if err != nil {
		h.logger.Error("conversation_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := conversationListResponse{Items: make([]conversationDTO, 0, len(items))}
	for _, c := range items {
		resp.Items = append(resp.Items, h.toConversationDTO(r, c))
	}
	writeJSON(w, http.StatusOK, resp)
}

// Start abre (ou recupera) a conversa entre o coach autenticado e um aluno
// do tenant — "qualquer professor do tenant" é o mesmo critério do
// P1.4/P2.1/P2.3; o vínculo coach↔aluno segue dívida do identity.
func (h *ConversationHandler) Start(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req struct {
		StudentID string `json:"student_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	studentID := strings.TrimSpace(req.StudentID)
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("student_id"))
		return
	}

	conv, err := h.conversations.GetOrCreate(r.Context(), claims.TenantID, studentID, claims.Subject)
	if err != nil {
		h.logger.Error("conversation_start_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, h.toConversationDTO(r, domain.ConversationSummary{Conversation: conv}))
}

// ListMessages devolve o histórico de uma conversa em cursor desc — só um
// participante (aluno ou coach da conversa) pode ler.
func (h *ConversationHandler) ListMessages(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	conv, apiErr := h.loadParticipantConversation(r, claims.TenantID, claims.Subject)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	cursorAt, cursorID, limit, apiErr := parseListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	items, hasMore, err := h.messages.List(r.Context(), claims.TenantID, conv.ID, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("message_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := messageListResponse{Items: make([]messageDTO, 0, len(items))}
	for _, m := range items {
		resp.Items = append(resp.Items, h.toMessageDTO(r, m))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.CreatedAt, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// SendMessage grava uma mensagem (texto ou imagem) e publica `message.new`
// para os dois participantes — quem estiver com WS aberto recebe na hora;
// quem não estiver recupera pelo próprio ListMessages ao reconectar (WS é só
// entrega quente, a verdade é o banco).
func (h *ConversationHandler) SendMessage(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	conv, apiErr := h.loadParticipantConversation(r, claims.TenantID, claims.Subject)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	var req struct {
		Type     string `json:"type"`
		Body     string `json:"body"`
		MediaKey string `json:"media_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	msgType := domain.MessageType(strings.TrimSpace(req.Type))
	if !domain.IsValidMessageType(msgType) {
		writeError(w, errValidation("type"))
		return
	}
	body := strings.TrimSpace(req.Body)
	if len(body) > maxMessageBodyLen {
		writeError(w, errValidation("body"))
		return
	}
	mediaKey := strings.TrimSpace(req.MediaKey)

	switch msgType {
	case domain.MessageTypeText:
		if body == "" {
			writeError(w, errValidation("body"))
			return
		}
		if mediaKey != "" {
			writeError(w, errValidation("media_key"))
			return
		}
	case domain.MessageTypeImage:
		if mediaKey == "" {
			writeError(w, errValidation("media_key"))
			return
		}
		// Par de segurança do presign: a key só é aceita dentro da pasta desta
		// conversa — sem isso um participante poderia anexar a mídia de outra
		// conversa (inclusive de outro tenant).
		if !media.ValidKeyForConversation(mediaKey, claims.TenantID, conv.ID) {
			writeError(w, errInvalidMediaKey())
			return
		}
	}

	created, err := h.messages.Create(r.Context(), domain.Message{
		TenantID: claims.TenantID, ConversationID: conv.ID, SenderID: claims.Subject,
		Type: msgType, Body: body, MediaKey: mediaKey,
	})
	if err != nil {
		h.logger.Error("message_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	dto := h.toMessageDTO(r, created)
	h.publish(r, conv, wsEvent{Type: "message.new", ConversationID: conv.ID, Message: &dto})

	writeJSON(w, http.StatusCreated, dto)
}

// MarkRead marca como lidas as mensagens da conversa que o chamador ainda
// não tinha lido (enviadas pelo outro participante) e publica `message.read`
// — o remetente original vê o "lido" atualizar sem precisar de REST.
func (h *ConversationHandler) MarkRead(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	conv, apiErr := h.loadParticipantConversation(r, claims.TenantID, claims.Subject)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	ids, err := h.messages.MarkRead(r.Context(), claims.TenantID, conv.ID, claims.Subject)
	if err != nil {
		h.logger.Error("message_mark_read_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if len(ids) > 0 {
		now := time.Now().UTC()
		h.publish(r, conv, wsEvent{
			Type: "message.read", ConversationID: conv.ID,
			ReaderID: claims.Subject, MessageIDs: ids, ReadAt: &now,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"marked": len(ids)})
}

// loadParticipantConversation resolve o id da conversa na URL, confere que
// ela existe no tenant e que o chamador é um dos dois participantes — 404
// tanto para id inexistente quanto para tenant errado (RLS já filtrou), 403
// para tenant certo mas usuário de fora da conversa.
func (h *ConversationHandler) loadParticipantConversation(r *http.Request, tenantID, userID string) (domain.Conversation, *APIError) {
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		return domain.Conversation{}, ptr(errValidation("id"))
	}
	conv, err := h.conversations.Get(r.Context(), tenantID, id)
	if errors.Is(err, repo.ErrNotFound) {
		return domain.Conversation{}, ptr(errNotFound("conversation"))
	}
	if err != nil {
		h.logger.Error("conversation_load_failed", slog.Any("error", err))
		return domain.Conversation{}, ptr(errInternal())
	}
	if userID != conv.StudentID && userID != conv.CoachID {
		return domain.Conversation{}, ptr(errForbidden())
	}
	return conv, nil
}

// publish serializa o evento e publica no canal Redis dos dois participantes
// (internal/pubsub). Falha ao publicar não derruba a requisição — a mensagem
// já está no banco, e o cliente recupera o gap via REST.
func (h *ConversationHandler) publish(r *http.Request, conv domain.Conversation, event wsEvent) {
	payload, err := json.Marshal(event)
	if err != nil {
		h.logger.Error("ws_event_marshal_failed", slog.Any("error", err))
		return
	}
	for _, userID := range []string{conv.StudentID, conv.CoachID} {
		if err := pubsub.PublishToUser(r.Context(), h.redisClient, userID, payload); err != nil {
			h.logger.Error("ws_event_publish_failed", slog.Any("error", err), slog.String("user_id", userID))
		}
	}
}

func (h *ConversationHandler) toConversationDTO(r *http.Request, s domain.ConversationSummary) conversationDTO {
	dto := conversationDTO{
		ID: s.ID, StudentID: s.StudentID, CoachID: s.CoachID,
		CreatedAt: s.CreatedAt, LastMessageAt: s.LastMessageAt, UnreadCount: s.UnreadCount,
	}
	if s.LastMessage != nil {
		lm := h.toMessageDTO(r, *s.LastMessage)
		dto.LastMessage = &lm
	}
	return dto
}

func (h *ConversationHandler) toMessageDTO(r *http.Request, m domain.Message) messageDTO {
	dto := messageDTO{
		ID: m.ID, ConversationID: m.ConversationID, SenderID: m.SenderID,
		Type: string(m.Type), Body: m.Body, CreatedAt: m.CreatedAt, ReadAt: m.ReadAt,
	}
	if m.Type == domain.MessageTypeImage && m.MediaKey != "" {
		mediaURL, err := h.presigner.ReadURL(r.Context(), m.MediaKey)
		if err != nil {
			h.logger.Error("message_read_url_failed", slog.Any("error", err))
		}
		dto.MediaURL = mediaURL
	}
	return dto
}

func ptr(e APIError) *APIError { return &e }
