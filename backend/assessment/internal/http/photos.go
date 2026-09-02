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

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/media"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// PhotoHandler expõe as fotos de evolução (ADR-012 §2): aluno lança/lê/apaga
// as próprias, coach lança/lê/apaga as de qualquer aluno do tenant. O
// `media_key` do corpo é sempre o devolvido por POST /media/presign — o
// handler confere que ele aponta para a pasta do aluno alvo antes de gravar.
type PhotoHandler struct {
	logger    *slog.Logger
	photos    *repo.PhotoRepo
	presigner *media.Presigner
}

// NewPhotoHandler cria o handler de fotos de evolução.
func NewPhotoHandler(logger *slog.Logger, photos *repo.PhotoRepo, presigner *media.Presigner) *PhotoHandler {
	return &PhotoHandler{logger: logger, photos: photos, presigner: presigner}
}

type photoRequest struct {
	TakenAt  string `json:"taken_at"`
	Pose     string `json:"pose"`
	MediaKey string `json:"media_key"`
	Notes    string `json:"notes"`
}

type photoDTO struct {
	ID        string    `json:"id"`
	StudentID string    `json:"student_id"`
	TakenAt   string    `json:"taken_at"`
	Pose      string    `json:"pose"`
	MediaURL  string    `json:"media_url"`
	Notes     string    `json:"notes,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type photoListResponse struct {
	Items      []photoDTO `json:"items"`
	NextCursor string     `json:"next_cursor,omitempty"`
}

func (h *PhotoHandler) CreateMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.create(w, r, claims.TenantID, claims.Subject)
}

func (h *PhotoHandler) CreateForStudent(w http.ResponseWriter, r *http.Request) {
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
	h.create(w, r, tenantID, studentID)
}

func (h *PhotoHandler) ListMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.list(w, r, claims.TenantID, claims.Subject)
}

func (h *PhotoHandler) ListForStudent(w http.ResponseWriter, r *http.Request) {
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
	h.list(w, r, tenantID, studentID)
}

func (h *PhotoHandler) DeleteMine(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.delete(w, r, claims.TenantID, claims.Subject)
}

func (h *PhotoHandler) DeleteForStudent(w http.ResponseWriter, r *http.Request) {
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
	h.delete(w, r, tenantID, studentID)
}

func (h *PhotoHandler) create(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	var req photoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	takenAt, apiErr := parseRequiredDate(req.TakenAt, "taken_at")
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	pose := domain.Pose(strings.TrimSpace(req.Pose))
	if !domain.IsValidPose(pose) {
		writeError(w, errValidation("pose"))
		return
	}
	key := strings.TrimSpace(req.MediaKey)
	if key == "" {
		writeError(w, errValidation("media_key"))
		return
	}
	// Par de segurança do presign: a key só é aceita dentro da pasta deste
	// aluno — sem isso um token do tenant A poderia gravar uma foto apontando
	// para a pasta de outro aluno.
	if !media.ValidKeyForStudent(key, tenantID, studentID) {
		writeError(w, errInvalidMediaKey())
		return
	}
	notes := strings.TrimSpace(req.Notes)
	if len(notes) > maxNotesLen {
		writeError(w, errValidation("notes"))
		return
	}

	photo := domain.ProgressPhoto{
		TenantID: tenantID, StudentID: studentID, TakenAt: takenAt,
		Pose: pose, MediaKey: key, Notes: notes,
	}
	created, err := h.photos.Create(r.Context(), photo)
	if err != nil {
		h.logger.Error("photo_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusCreated, h.toDTO(r, created))
}

func (h *PhotoHandler) list(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	cursorAt, cursorID, limit, apiErr := parseListQuery(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	items, hasMore, err := h.photos.List(r.Context(), tenantID, studentID, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("photo_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := photoListResponse{Items: make([]photoDTO, 0, len(items))}
	for _, p := range items {
		resp.Items = append(resp.Items, h.toDTO(r, p))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.TakenAt, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *PhotoHandler) delete(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	id := chi.URLParam(r, "photo_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("photo_id"))
		return
	}
	err := h.photos.Delete(r.Context(), tenantID, studentID, id)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("photo"))
		return
	}
	if err != nil {
		h.logger.Error("photo_delete_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *PhotoHandler) toDTO(r *http.Request, p domain.ProgressPhoto) photoDTO {
	mediaURL, err := h.presigner.ReadURL(r.Context(), p.MediaKey)
	if err != nil {
		h.logger.Error("photo_read_url_failed", slog.Any("error", err))
	}
	return photoDTO{
		ID: p.ID, StudentID: p.StudentID, TakenAt: p.TakenAt.Format(time.DateOnly),
		Pose: string(p.Pose), MediaURL: mediaURL, Notes: p.Notes, CreatedAt: p.CreatedAt,
	}
}
