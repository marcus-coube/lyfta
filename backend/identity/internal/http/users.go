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

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// UserHandler expõe a listagem de usuários do tenant (P1.6): é dela que a
// tela de alunos do professor tira a lista para montar plano.
//
// O `workout` não consegue responder isso — o vínculo aluno↔tenant vive aqui
// e nenhum serviço lê o banco do outro (ADR-013 §2).
type UserHandler struct {
	logger *slog.Logger
	users  *repo.UserRepo
	links  *repo.CoachLinkRepo
}

// NewUserHandler cria o handler de usuários.
func NewUserHandler(logger *slog.Logger, users *repo.UserRepo, links *repo.CoachLinkRepo) *UserHandler {
	return &UserHandler{logger: logger, users: users, links: links}
}

// hasRole diz se as claims trazem o papel.
func hasRole(claims *security.Claims, role domain.Role) bool {
	for _, r := range claims.Roles {
		if r == string(role) {
			return true
		}
	}
	return false
}

type userResponse struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Roles     []string  `json:"roles"`
	Status    string    `json:"status"`
	Locale    string    `json:"locale"`
	CreatedAt time.Time `json:"created_at"`
	// Professor vinculado (alunos, ADR-016).
	CoachID   string `json:"coach_id,omitempty"`
	CoachName string `json:"coach_name,omitempty"`
}

type userListResponse struct {
	Items      []userResponse `json:"items"`
	NextCursor string         `json:"next_cursor,omitempty"`
}

// List responde os usuários do tenant, com filtro por papel e busca por nome
// ou e-mail. Restrito a owner|coach: a lista de alunos é dado da academia.
func (h *UserHandler) List(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	q := r.URL.Query()
	filter := repo.UserFilter{Query: strings.TrimSpace(q.Get("q"))}

	if raw := strings.TrimSpace(q.Get("role")); raw != "" {
		role := domain.Role(raw)
		if !isKnownRole(role) {
			// Papel fora do vocabulário é erro de contrato, não lista vazia:
			// o cliente saberia que errou só depois de estranhar a tela.
			writeError(w, errValidation("role"))
			return
		}
		filter.Role = role
	}
	if raw := strings.TrimSpace(q.Get("status")); raw != "" {
		status := domain.UserStatus(raw)
		if !isKnownStatus(status) {
			writeError(w, errValidation("status"))
			return
		}
		filter.Status = status
	}
	// Escopo do vínculo (ADR-016 §2): owner vê todos e pode filtrar por
	// professor; coach sem owner só vê os alunos dele.
	if hasRole(claims, domain.RoleOwner) {
		if raw := strings.TrimSpace(q.Get("coach_id")); raw != "" {
			if _, err := uuid.Parse(raw); err != nil {
				writeError(w, errValidation("coach_id"))
				return
			}
			filter.CoachID = raw
		}
	} else {
		if filter.Role != "" && filter.Role != domain.RoleStudent {
			writeError(w, errForbidden())
			return
		}
		filter.Role = domain.RoleStudent
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
		h.logger.Error("users_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := userListResponse{Items: make([]userResponse, 0, len(users))}
	for _, u := range users {
		roles := make([]string, 0, len(u.Roles))
		for _, role := range u.Roles {
			roles = append(roles, string(role))
		}
		item := userResponse{
			ID: u.ID, Name: u.Name, Email: u.Email, Roles: roles,
			Status: string(u.Status), Locale: u.Locale, CreatedAt: u.CreatedAt,
		}
		if u.CoachID != nil {
			item.CoachID = *u.CoachID
		}
		if u.CoachName != nil {
			item.CoachName = *u.CoachName
		}
		resp.Items = append(resp.Items, item)
	}
	if hasMore && len(users) > 0 {
		last := users[len(users)-1]
		resp.NextCursor = encodeCursor(last.Name, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

func isKnownRole(role domain.Role) bool {
	switch role {
	case domain.RoleOwner, domain.RoleCoach, domain.RoleStudent:
		return true
	default:
		return false
	}
}

func isKnownStatus(status domain.UserStatus) bool {
	switch status {
	case domain.UserStatusInvited, domain.UserStatusActive, domain.UserStatusDisabled:
		return true
	default:
		return false
	}
}

// encodeCursor/decodeCursor empacotam a chave keyset (nome + id). Opaco de
// propósito: o cliente devolve o que recebeu, e a composição da chave pode
// mudar sem quebrar contrato.
const cursorSeparator = "\x1f"

func encodeCursor(sortKey, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(sortKey + cursorSeparator + id))
}

func decodeCursor(raw string) (sortKey, id string, err error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return "", "", err
	}
	parts := strings.SplitN(string(decoded), cursorSeparator, 2)
	if len(parts) != 2 || parts[1] == "" {
		return "", "", errors.New("http: cursor malformado")
	}
	return parts[0], parts[1], nil
}

type putCoachRequest struct {
	CoachID string `json:"coach_id"`
}

// PutStudentCoach — PUT /v1/students/{id}/coach (só owner, ADR-016 §1):
// reatribui o professor do aluno. 422 se o aluno não existe/foi excluído ou se
// o coach não é um usuário ativo com papel coach|owner.
func (h *UserHandler) PutStudentCoach(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	studentID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errUnprocessable("id"))
		return
	}
	var req putCoachRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if _, err := uuid.Parse(req.CoachID); err != nil {
		writeError(w, errUnprocessable("coach_id"))
		return
	}
	err := h.links.Reassign(r.Context(), claims.TenantID, studentID, req.CoachID, claims.Subject)
	if errors.Is(err, repo.ErrInvalidLink) {
		writeError(w, errUnprocessable("coach_id"))
		return
	}
	if err != nil {
		h.logger.Error("student_coach_reassign_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"student_id": studentID, "coach_id": req.CoachID})
}

// internalIDs lê {id} da rota e tenant_id da query, ambos UUID.
func internalIDs(w http.ResponseWriter, r *http.Request) (id, tenantID string, ok bool) {
	id = chi.URLParam(r, "id")
	tenantID = r.URL.Query().Get("tenant_id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, errValidation("id"))
		return "", "", false
	}
	if _, err := uuid.Parse(tenantID); err != nil {
		writeError(w, errValidation("tenant_id"))
		return "", "", false
	}
	return id, tenantID, true
}

// InternalCoachStudents — GET /internal/v1/coaches/{id}/students?tenant_id=
// (M2M, ADR-016 §3): os alunos vinculados ao coach.
func (h *UserHandler) InternalCoachStudents(w http.ResponseWriter, r *http.Request) {
	coachID, tenantID, ok := internalIDs(w, r)
	if !ok {
		return
	}
	ids, err := h.links.StudentIDs(r.Context(), tenantID, coachID)
	if err != nil {
		h.logger.Error("internal_coach_students_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"student_ids": ids})
}

// InternalStudentCoach — GET /internal/v1/students/{id}/coach?tenant_id=
// (M2M, ADR-016 §3): o professor atual do aluno; 404 `student_not_found` sem
// vínculo.
func (h *UserHandler) InternalStudentCoach(w http.ResponseWriter, r *http.Request) {
	studentID, tenantID, ok := internalIDs(w, r)
	if !ok {
		return
	}
	coachID, err := h.links.CoachOf(r.Context(), tenantID, studentID)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errStudentNotFound())
		return
	}
	if err != nil {
		h.logger.Error("internal_student_coach_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"coach_id": coachID})
}
