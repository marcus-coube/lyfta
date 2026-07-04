package http

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// AuthHandler concentra as dependências dos endpoints de tenants/auth
// (P0.3): repositórios e o signer JWT.
type AuthHandler struct {
	logger  *slog.Logger
	tenants *repo.TenantRepo
	users   *repo.UserRepo
	auth    *repo.AuthRepo
	jwt     *security.JWTSigner
}

// NewAuthHandler cria um AuthHandler com as dependências informadas.
func NewAuthHandler(logger *slog.Logger, tenants *repo.TenantRepo, users *repo.UserRepo, auth *repo.AuthRepo, jwt *security.JWTSigner) *AuthHandler {
	return &AuthHandler{logger: logger, tenants: tenants, users: users, auth: auth, jwt: jwt}
}

var slugPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// tokenResponse é o corpo devolvido por signup/login/refresh bem-sucedidos.
type tokenResponse struct {
	AccessToken  string   `json:"access_token"`
	RefreshToken string   `json:"refresh_token"`
	ExpiresAt    string   `json:"expires_at"`
	TenantID     string   `json:"tenant_id"`
	UserID       string   `json:"user_id"`
	Roles        []string `json:"roles"`
}

// --- POST /v1/tenants (público) ---------------------------------------

type signupRequest struct {
	BusinessName string `json:"business_name"`
	Slug         string `json:"slug"`
	Name         string `json:"name"`
	Email        string `json:"email"`
	Password     string `json:"password"`
	Locale       string `json:"locale"`
}

// Signup cria um tenant novo + o usuário owner/coach numa transação
// (P0.3). Endpoint público.
func (h *AuthHandler) Signup(w http.ResponseWriter, r *http.Request) {
	var req signupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	req.BusinessName = strings.TrimSpace(req.BusinessName)
	req.Slug = strings.TrimSpace(strings.ToLower(req.Slug))
	req.Name = strings.TrimSpace(req.Name)
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Locale == "" {
		req.Locale = "pt-BR"
	}

	switch {
	case req.BusinessName == "":
		writeError(w, errValidation("business_name"))
		return
	case !slugPattern.MatchString(req.Slug):
		writeError(w, errValidation("slug"))
		return
	case req.Name == "":
		writeError(w, errValidation("name"))
		return
	case !strings.Contains(req.Email, "@"):
		writeError(w, errValidation("email"))
		return
	case len(req.Password) < 8:
		writeError(w, errValidation("password"))
		return
	}

	ctx := r.Context()

	if _, err := h.tenants.FindBySlug(ctx, req.Slug); err == nil {
		writeError(w, errSlugTaken())
		return
	} else if err != repo.ErrNotFound {
		h.logger.Error("signup_find_slug_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	passwordHash, err := security.HashPassword(req.Password)
	if err != nil {
		h.logger.Error("signup_hash_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	_, user, err := h.tenants.CreateWithOwner(ctx,
		domain.Tenant{
			Name:   req.BusinessName,
			Slug:   req.Slug,
			Locale: req.Locale,
		},
		domain.User{
			Email:        req.Email,
			PasswordHash: passwordHash,
			Name:         req.Name,
			Locale:       req.Locale,
			Status:       domain.UserStatusActive,
			Roles:        []domain.Role{domain.RoleOwner, domain.RoleCoach},
		},
	)
	if err != nil {
		h.logger.Error("signup_create_tenant_and_owner_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp, apiErr := h.issueTokens(ctx, user)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

// --- POST /v1/auth/login -------------------------------------------------

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	TenantID string `json:"tenant_id"`
}

// Login autentica por e-mail+senha. Se o e-mail existir em vários tenants e
// tenant_id não vier no corpo, devolve 409 multiple_tenants (ADR-002 §2c)
// com a lista para o cliente escolher e reenviar.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || req.Password == "" {
		writeError(w, errInvalidCredentials())
		return
	}

	ctx := r.Context()

	matches, err := h.auth.FindTenantsByEmail(ctx, req.Email)
	if err != nil {
		h.logger.Error("login_find_tenants_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if len(matches) == 0 {
		writeError(w, errInvalidCredentials())
		return
	}

	var chosen *domain.TenantMatch
	if req.TenantID != "" {
		for i := range matches {
			if matches[i].TenantID == req.TenantID {
				chosen = &matches[i]
				break
			}
		}
		if chosen == nil {
			writeError(w, errInvalidCredentials())
			return
		}
	} else if len(matches) == 1 {
		chosen = &matches[0]
	} else {
		options := make([]tenantOption, 0, len(matches))
		for _, m := range matches {
			options = append(options, tenantOption{TenantID: m.TenantID, TenantName: m.TenantName})
		}
		writeError(w, errMultipleTenants(options))
		return
	}

	user, err := h.users.FindByEmailInTenant(ctx, chosen.TenantID, req.Email)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidCredentials())
			return
		}
		h.logger.Error("login_find_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	ok, err := security.VerifyPassword(req.Password, user.PasswordHash)
	if err != nil || !ok {
		writeError(w, errInvalidCredentials())
		return
	}

	resp, apiErr := h.issueTokens(ctx, user)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// --- POST /v1/auth/refresh ------------------------------------------------

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
	TenantID     string `json:"tenant_id"`
}

// Refresh roda a rotação do refresh token: o token recebido é validado e
// revogado, e um novo par access+refresh é emitido (P0.3).
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if req.RefreshToken == "" || req.TenantID == "" {
		writeError(w, errInvalidToken())
		return
	}

	ctx := r.Context()
	tokenHash := repo.HashToken(req.RefreshToken)

	rt, err := h.auth.FindValidRefreshToken(ctx, req.TenantID, tokenHash)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidToken())
			return
		}
		h.logger.Error("refresh_find_token_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if err := h.auth.RevokeRefreshToken(ctx, req.TenantID, rt.ID); err != nil {
		h.logger.Error("refresh_revoke_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	user, err := h.auth.FindUserByID(ctx, req.TenantID, rt.UserID)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidToken())
			return
		}
		h.logger.Error("refresh_find_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp, apiErr := h.issueTokens(ctx, user)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// --- POST /v1/auth/logout -------------------------------------------------

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
	TenantID     string `json:"tenant_id"`
}

// Logout revoga o refresh token informado. Idempotente: token já revogado
// ou inexistente ainda responde 204 (não vaza se o token existia).
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if req.RefreshToken == "" || req.TenantID == "" {
		writeError(w, errInvalidToken())
		return
	}

	ctx := r.Context()
	tokenHash := repo.HashToken(req.RefreshToken)

	rt, err := h.auth.FindValidRefreshToken(ctx, req.TenantID, tokenHash)
	if err != nil {
		if err == repo.ErrNotFound {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.logger.Error("logout_find_token_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if err := h.auth.RevokeRefreshToken(ctx, req.TenantID, rt.ID); err != nil {
		h.logger.Error("logout_revoke_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- helpers ---------------------------------------------------------------

// issueTokens assina um novo access token e cria um novo refresh token para
// o usuário informado, devolvendo o envelope de resposta comum aos três
// endpoints que emitem sessão (signup, login, refresh).
func (h *AuthHandler) issueTokens(ctx context.Context, user domain.User) (tokenResponse, *APIError) {
	roles := make([]string, 0, len(user.Roles))
	for _, role := range user.Roles {
		roles = append(roles, string(role))
	}

	access, expiresAt, err := h.jwt.Sign(user.ID, user.TenantID, roles, user.Locale)
	if err != nil {
		h.logger.Error("issue_tokens_sign_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	refreshPlain, err := generateOpaqueToken()
	if err != nil {
		h.logger.Error("issue_tokens_refresh_gen_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	if _, err := h.auth.CreateRefreshToken(ctx, user.TenantID, user.ID, repo.HashToken(refreshPlain), time.Now().Add(repo.RefreshTokenTTL)); err != nil {
		h.logger.Error("issue_tokens_create_refresh_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	return tokenResponse{
		AccessToken:  access,
		RefreshToken: refreshPlain,
		ExpiresAt:    expiresAt.UTC().Format(time.RFC3339),
		TenantID:     user.TenantID,
		UserID:       user.ID,
		Roles:        roles,
	}, nil
}

// generateOpaqueToken gera um refresh token opaco aleatório (256 bits).
func generateOpaqueToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}
