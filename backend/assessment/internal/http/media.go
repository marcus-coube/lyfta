package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/media"
)

// MediaHandler assina uploads de foto de evolução (P2.3). O serviço não
// recebe bytes: devolve uma URL assinada para o app fazer PUT direto no
// storage — mesmo contrato do workout (P1.2), com a key carregando o aluno.
type MediaHandler struct {
	logger    *slog.Logger
	presigner *media.Presigner
	consents  ConsentChecker
}

// NewMediaHandler cria o handler de mídia sobre o presigner configurado.
func NewMediaHandler(logger *slog.Logger, presigner *media.Presigner, consents ConsentChecker) *MediaHandler {
	return &MediaHandler{logger: logger, presigner: presigner, consents: consents}
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

// PresignMine assina o upload de uma foto do próprio aluno.
func (h *MediaHandler) PresignMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	// Sem consentimento em fotos o aluno nem começa o upload (ADR-008 §1).
	if !mineHasPhotoConsent(claims) {
		writeError(w, errConsentRequired(PurposeProgressPhotos))
		return
	}
	h.presign(w, r, claims.TenantID, claims.Subject)
}

// PresignForStudent assina o upload de uma foto lançada pelo coach.
func (h *MediaHandler) PresignForStudent(w http.ResponseWriter, r *http.Request) {
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
	if !requireStudentPhotoConsent(w, r, h.logger, h.consents, tenantID, studentID) {
		return
	}
	h.presign(w, r, tenantID, studentID)
}

// presign monta a URL assinada. O tenant e o aluno do caminho do objeto vêm
// sempre da claim/URL, nunca do corpo — quem tem token de um tenant/aluno não
// consegue assinar um upload dentro da pasta de outro.
func (h *MediaHandler) presign(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
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

	key, err := media.ObjectKey(tenantID, studentID, extension)
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
