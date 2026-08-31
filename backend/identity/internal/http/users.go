package http

import (
	"encoding/base64"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
)

// UserHandler expõe a listagem de usuários do tenant (P1.6): é dela que a
// tela de alunos do professor tira a lista para montar plano.
//
// O `workout` não consegue responder isso — o vínculo aluno↔tenant vive aqui
// e nenhum serviço lê o banco do outro (ADR-013 §2).
type UserHandler struct {
	logger *slog.Logger
	users  *repo.UserRepo
}

// NewUserHandler cria o handler de usuários.
func NewUserHandler(logger *slog.Logger, users *repo.UserRepo) *UserHandler {
	return &UserHandler{logger: logger, users: users}
}

type userResponse struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Roles     []string  `json:"roles"`
	Status    string    `json:"status"`
	Locale    string    `json:"locale"`
	CreatedAt time.Time `json:"created_at"`
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
		resp.Items = append(resp.Items, userResponse{
			ID: u.ID, Name: u.Name, Email: u.Email, Roles: roles,
			Status: string(u.Status), Locale: u.Locale, CreatedAt: u.CreatedAt,
		})
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
