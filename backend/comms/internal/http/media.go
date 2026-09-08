package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/media"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// MediaHandler assina uploads de imagem de chat (P3.2). O serviço não recebe
// bytes: devolve uma URL assinada para o app fazer PUT direto no storage —
// mesmo contrato do workout/assessment, com a key carregando a conversa.
type MediaHandler struct {
	logger        *slog.Logger
	conversations *repo.ConversationRepo
	presigner     *media.Presigner
}

// NewMediaHandler cria o handler de mídia sobre o presigner configurado.
func NewMediaHandler(logger *slog.Logger, conversations *repo.ConversationRepo, presigner *media.Presigner) *MediaHandler {
	return &MediaHandler{logger: logger, conversations: conversations, presigner: presigner}
}

type presignRequest struct {
	ContentType string `json:"content_type"`
	SizeBytes   int64  `json:"size_bytes"`
}

type presignResponse struct {
	UploadURL string            `json:"upload_url"`
	Method    string            `json:"upload_method"`
	Headers   map[string]string `json:"required_headers"`
	Key       string            `json:"key"`
	ExpiresAt time.Time         `json:"expires_at"`
}

// Presign assina o upload de uma imagem para a conversa {id} — só um
// participante (aluno ou coach da conversa) pode pedir a assinatura.
func (h *MediaHandler) Presign(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	convID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(convID); err != nil {
		writeError(w, errValidation("id"))
		return
	}

	conv, err := h.conversations.Get(r.Context(), claims.TenantID, convID)
	if err != nil {
		writeError(w, errNotFound("conversation"))
		return
	}
	if claims.Subject != conv.StudentID && claims.Subject != conv.CoachID {
		writeError(w, errForbidden())
		return
	}

	var req presignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	extension, ok := media.LookupType(req.ContentType)
	if !ok {
		writeError(w, errUnsupportedMediaType(req.ContentType))
		return
	}
	if req.SizeBytes <= 0 {
		writeError(w, errValidation("size_bytes"))
		return
	}
	if req.SizeBytes > media.MaxUploadBytes {
		writeError(w, errFileTooLarge(media.MaxUploadBytes))
		return
	}

	key, err := media.ObjectKey(claims.TenantID, convID, extension)
	if err != nil {
		h.logger.Error("media_key_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	uploadURL, expiresAt, err := h.presigner.PresignPut(r.Context(), key, req.ContentType, req.SizeBytes)
	if err != nil {
		h.logger.Error("media_presign_put_failed", slog.Any("error", err))
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
