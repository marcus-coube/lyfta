package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/marcus-coube/lyfta/workout/internal/media"
)

// MediaHandler assina uploads de mídia de exercício (P1.2). O serviço não
// recebe bytes: devolve uma URL assinada para o app fazer PUT direto no
// storage.
type MediaHandler struct {
	logger    *slog.Logger
	presigner *media.Presigner
}

// NewMediaHandler cria o handler de mídia sobre o presigner configurado.
func NewMediaHandler(logger *slog.Logger, presigner *media.Presigner) *MediaHandler {
	return &MediaHandler{logger: logger, presigner: presigner}
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
	MediaURL  string            `json:"media_url"`
	MediaType string            `json:"media_type"`
	ExpiresAt time.Time         `json:"expires_at"`
}

// Presign responde a URL assinada de upload e a URL de exibição da mídia.
//
// O tenant do caminho do objeto vem da claim, nunca do body: quem tem token do
// tenant A não consegue assinar um upload dentro da pasta do tenant B.
func (h *MediaHandler) Presign(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}

	var req presignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	allowed, ok := media.LookupType(req.ContentType)
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

	key, err := media.ObjectKey(tenantID, allowed.Extension)
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

	mediaURL, err := h.presigner.ReadURL(r.Context(), key)
	if err != nil {
		h.logger.Error("media_presign_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	writeJSON(w, http.StatusOK, presignResponse{
		UploadURL: uploadURL,
		Method:    http.MethodPut,
		// Os dois headers entram na assinatura: mandar valores diferentes faz
		// o storage recusar o upload.
		Headers: map[string]string{
			"Content-Type":   req.ContentType,
			"Content-Length": strconv.FormatInt(req.SizeBytes, 10),
		},
		Key:       key,
		MediaURL:  mediaURL,
		MediaType: string(allowed.MediaType),
		ExpiresAt: expiresAt,
	})
}
