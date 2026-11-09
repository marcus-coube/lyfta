package http

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// StudentHandler expõe o cadastro e o ciclo de vida do aluno (P5.2): lista,
// ficha, edição, inativar/reativar e histórico. Acesso: owner vê todos; coach
// só os alunos vinculados a ele (ADR-016) — aluno de outro coach responde 404
// `student_not_found`, igual a aluno inexistente.
type StudentHandler struct {
	logger   *slog.Logger
	users    *repo.UserRepo
	students *repo.StudentRepo
	links    *repo.CoachLinkRepo
}

// NewStudentHandler cria o handler de alunos.
func NewStudentHandler(logger *slog.Logger, users *repo.UserRepo, students *repo.StudentRepo, links *repo.CoachLinkRepo) *StudentHandler {
	return &StudentHandler{logger: logger, users: users, students: students, links: links}
}

type studentResponse struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Phone     *string   `json:"phone"`
	BirthDate *string   `json:"birth_date"`
	Status    string    `json:"status"`
	Locale    string    `json:"locale"`
	CreatedAt time.Time `json:"created_at"`
	CoachID   string    `json:"coach_id,omitempty"`
	CoachName string    `json:"coach_name,omitempty"`
	// Só na ficha, com o aluno ainda `invited`: o convite a reenviar.
	PendingInvitation *pendingInvitationResponse `json:"pending_invitation,omitempty"`
}

type pendingInvitationResponse struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
	Expired   bool      `json:"expired"`
}

func toStudentResponse(u domain.User) studentResponse {
	item := studentResponse{
		ID: u.ID, Name: u.Name, Email: u.Email, Phone: u.Phone, BirthDate: u.BirthDate,
		Status: string(u.Status), Locale: u.Locale, CreatedAt: u.CreatedAt,
	}
	if u.CoachID != nil {
		item.CoachID = *u.CoachID
	}
	if u.CoachName != nil {
		item.CoachName = *u.CoachName
	}
	return item
}

type studentListResponse struct {
	Items      []studentResponse `json:"items"`
	NextCursor string            `json:"next_cursor,omitempty"`
}

// List — GET /v1/students: owner|coach. Filtros `status` (omitido esconde os
// inativos), `coach_id` (só owner; coach sempre vê os próprios), `q` (nome ou
// e-mail), `limit` (página, teto 200) e `cursor`. Ordenado por nome; o cursor
// pagina a lista inteira, sem teto de itens.
func (h *StudentHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	q := r.URL.Query()
	filter := repo.UserFilter{Role: domain.RoleStudent, Query: strings.TrimSpace(q.Get("q"))}

	if raw := strings.TrimSpace(q.Get("status")); raw != "" {
		status := domain.UserStatus(raw)
		if !isKnownStatus(status) {
			writeError(w, errValidation("status"))
			return
		}
		filter.Status = status
	}
	if hasRole(claims, domain.RoleOwner) {
		if raw := strings.TrimSpace(q.Get("coach_id")); raw != "" {
			if _, err := uuid.Parse(raw); err != nil {
				writeError(w, errValidation("coach_id"))
				return
			}
			filter.CoachID = raw
		}
	} else {
		filter.CoachID = claims.Subject
	}
	if raw := strings.TrimSpace(q.Get("limit")); raw != "" {
		limit, err := strconv.Atoi(raw)
		if err != nil || limit <= 0 || limit > repo.MaxUserPageSize {
			writeError(w, errValidation("limit"))
			return
		}
		filter.Limit = limit
	}
	if raw := strings.TrimSpace(q.Get("cursor")); raw != "" {
		name, id, err := decodeCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		filter.CursorName, filter.CursorID = name, id
	}

	users, hasMore, err := h.users.List(r.Context(), claims.TenantID, filter)
	if err != nil {
		h.logger.Error("students_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := studentListResponse{Items: make([]studentResponse, 0, len(users))}
	for _, u := range users {
		resp.Items = append(resp.Items, toStudentResponse(u))
	}
	if hasMore && len(users) > 0 {
		last := users[len(users)-1]
		resp.NextCursor = encodeCursor(last.Name, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// authorize resolve o aluno da rota e confere o acesso do ator: owner passa;
// coach só se for o professor vinculado. Qualquer falha de acesso é 404
// `student_not_found` (ADR-016 §4). Devolve ok=false depois de responder.
func (h *StudentHandler) authorize(w http.ResponseWriter, r *http.Request) (tenantID, studentID, actorID string, ok bool) {
	claims, found := ClaimsFromContext(r.Context())
	if !found || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return "", "", "", false
	}
	studentID = chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errStudentNotFound())
		return "", "", "", false
	}
	if !hasRole(claims, domain.RoleOwner) {
		coachID, err := h.links.CoachOf(r.Context(), claims.TenantID, studentID)
		if errors.Is(err, repo.ErrNotFound) || (err == nil && coachID != claims.Subject) {
			writeError(w, errStudentNotFound())
			return "", "", "", false
		}
		if err != nil {
			h.logger.Error("student_access_check_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return "", "", "", false
		}
	}
	return claims.TenantID, studentID, claims.Subject, true
}

// Get — GET /v1/students/{id}: cadastro, professor, status e convite pendente.
func (h *StudentHandler) Get(w http.ResponseWriter, r *http.Request) {
	tenantID, studentID, _, ok := h.authorize(w, r)
	if !ok {
		return
	}
	detail, err := h.students.Get(r.Context(), tenantID, studentID)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errStudentNotFound())
		return
	}
	if err != nil {
		h.logger.Error("student_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := toStudentResponse(detail.User)
	if inv := detail.PendingInvitation; inv != nil {
		resp.PendingInvitation = &pendingInvitationResponse{
			ID: inv.ID, CreatedAt: inv.CreatedAt, ExpiresAt: inv.ExpiresAt,
			Expired: !inv.ExpiresAt.After(time.Now()),
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

type patchProfileRequest struct {
	Name      *string `json:"name"`
	Phone     *string `json:"phone"`
	BirthDate *string `json:"birth_date"`
}

const (
	maxNameLen  = 120
	maxPhoneLen = 30
)

var phoneRe = regexp.MustCompile(`^[0-9+()\-. ]+$`)

// toPatch valida o corpo e devolve o patch; a string do campo inválido vem em
// `field` (422 validation_error). Telefone e nascimento aceitam "" para apagar.
func (req patchProfileRequest) toPatch(allowName bool) (p repo.ProfilePatch, field string) {
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if !allowName || name == "" || utf8.RuneCountInString(name) > maxNameLen {
			return p, "name"
		}
		p.Name = &name
	}
	if req.Phone != nil {
		phone := strings.TrimSpace(*req.Phone)
		if phone != "" && (len(phone) > maxPhoneLen || !phoneRe.MatchString(phone)) {
			return p, "phone"
		}
		p.Phone = &phone
	}
	if req.BirthDate != nil {
		birth := strings.TrimSpace(*req.BirthDate)
		if birth != "" {
			day, err := time.Parse("2006-01-02", birth)
			if err != nil || day.After(time.Now().UTC()) || day.Year() < 1900 {
				return p, "birth_date"
			}
		}
		p.BirthDate = &birth
	}
	return p, ""
}

// Patch — PATCH /v1/students/{id}: nome, telefone e nascimento (campo omitido
// mantém). Devolve a ficha atualizada.
func (h *StudentHandler) Patch(w http.ResponseWriter, r *http.Request) {
	tenantID, studentID, _, ok := h.authorize(w, r)
	if !ok {
		return
	}
	var req patchProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	patch, field := req.toPatch(true)
	if field != "" {
		writeError(w, errUnprocessable(field))
		return
	}
	if err := h.users.UpdateProfile(r.Context(), tenantID, studentID, patch); err != nil {
		if errors.Is(err, repo.ErrNotFound) {
			writeError(w, errStudentNotFound())
			return
		}
		h.logger.Error("student_patch_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	h.Get(w, r)
}

type statusChangeRequest struct {
	Reason string `json:"reason"`
}

const maxReasonLen = 500

// Deactivate — POST /v1/students/{id}/deactivate.
func (h *StudentHandler) Deactivate(w http.ResponseWriter, r *http.Request) {
	h.changeStatus(w, r, domain.UserStatusInactive)
}

// Reactivate — POST /v1/students/{id}/reactivate.
func (h *StudentHandler) Reactivate(w http.ResponseWriter, r *http.Request) {
	h.changeStatus(w, r, domain.UserStatusActive)
}

// changeStatus inativa ou reativa o aluno. O corpo é opcional (`reason`).
// Já no status pedido = 409 `already_inactive`/`already_active`; aluno que
// ainda não aceitou o convite (ou está `disabled`) = 409
// `invalid_status_transition`.
func (h *StudentHandler) changeStatus(w http.ResponseWriter, r *http.Request, to domain.UserStatus) {
	tenantID, studentID, actorID, ok := h.authorize(w, r)
	if !ok {
		return
	}
	var req statusChangeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		writeError(w, errInvalidBody())
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if utf8.RuneCountInString(reason) > maxReasonLen {
		writeError(w, errUnprocessable("reason"))
		return
	}
	err := h.students.SetStatus(r.Context(), tenantID, studentID, to, actorID, reason)
	switch {
	case err == nil:
		h.Get(w, r)
	case errors.Is(err, repo.ErrNotFound):
		writeError(w, errStudentNotFound())
	case errors.Is(err, repo.ErrAlreadyInStatus) && to == domain.UserStatusInactive:
		writeError(w, errAlreadyInactive())
	case errors.Is(err, repo.ErrAlreadyInStatus):
		writeError(w, errAlreadyActive())
	case errors.Is(err, repo.ErrInvalidTransition):
		writeError(w, errInvalidStatusTransition())
	default:
		h.logger.Error("student_status_change_failed", slog.Any("error", err))
		writeError(w, errInternal())
	}
}

type statusEventResponse struct {
	From          string    `json:"from"`
	To            string    `json:"to"`
	ChangedBy     string    `json:"changed_by"`
	ChangedByName string    `json:"changed_by_name"`
	Reason        *string   `json:"reason"`
	CreatedAt     time.Time `json:"created_at"`
}

// StatusHistory — GET /v1/students/{id}/status-history: as transições, da
// mais recente para a mais antiga (até repo.MaxStatusHistory).
func (h *StudentHandler) StatusHistory(w http.ResponseWriter, r *http.Request) {
	tenantID, studentID, _, ok := h.authorize(w, r)
	if !ok {
		return
	}
	events, err := h.students.StatusHistory(r.Context(), tenantID, studentID)
	if err != nil {
		h.logger.Error("student_status_history_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	items := make([]statusEventResponse, 0, len(events))
	for _, e := range events {
		items = append(items, statusEventResponse{
			From: e.From, To: e.To, ChangedBy: e.ChangedBy, ChangedByName: e.ChangedByName,
			Reason: e.Reason, CreatedAt: e.CreatedAt,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// MaxInternalStudentStatuses é o teto de alunos por chamada do M2M em lote.
const MaxInternalStudentStatuses = 500

type internalStudentRef struct {
	TenantID  string `json:"tenant_id"`
	StudentID string `json:"student_id"`
}

type internalStudentStatus struct {
	TenantID  string `json:"tenant_id"`
	StudentID string `json:"student_id"`
	Status    string `json:"status"`
}

// InternalStudentStatuses — POST /internal/v1/students/statuses (M2M): o
// status de vários alunos, de um ou mais tenants, numa chamada. O job de
// pendente do comms usa para ignorar inativos. Aluno que não existe no
// tenant (ou foi excluído) simplesmente não volta em `items`.
func (h *StudentHandler) InternalStudentStatuses(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Students []internalStudentRef `json:"students"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req); err != nil {
		writeError(w, errValidation("students"))
		return
	}
	if len(req.Students) == 0 || len(req.Students) > MaxInternalStudentStatuses {
		writeError(w, errValidation("students"))
		return
	}
	byTenant := map[string][]string{}
	for _, ref := range req.Students {
		if _, err := uuid.Parse(ref.TenantID); err != nil {
			writeError(w, errValidation("tenant_id"))
			return
		}
		if _, err := uuid.Parse(ref.StudentID); err != nil {
			writeError(w, errValidation("student_id"))
			return
		}
		byTenant[ref.TenantID] = append(byTenant[ref.TenantID], ref.StudentID)
	}

	items := make([]internalStudentStatus, 0, len(req.Students))
	for tenantID, ids := range byTenant {
		statuses, err := h.students.StatusesOf(r.Context(), tenantID, ids)
		if err != nil {
			h.logger.Error("internal_student_statuses_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		for id, status := range statuses {
			items = append(items, internalStudentStatus{TenantID: tenantID, StudentID: id, Status: string(status)})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}
