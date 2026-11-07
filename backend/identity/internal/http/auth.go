package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"sync"

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
	issuer  *SessionIssuer
	// termsVersion é a versão vigente dos termos (ADR-008 §6): o signup só
	// vale se o cliente diz ter aceitado exatamente essa.
	termsVersion string
}

// NewAuthHandler cria um AuthHandler com as dependências informadas.
func NewAuthHandler(logger *slog.Logger, tenants *repo.TenantRepo, users *repo.UserRepo, auth *repo.AuthRepo, issuer *SessionIssuer, termsVersion string) *AuthHandler {
	return &AuthHandler{logger: logger, tenants: tenants, users: users, auth: auth, issuer: issuer, termsVersion: termsVersion}
}

var slugPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// --- POST /v1/tenants (público) ---------------------------------------

type signupRequest struct {
	BusinessName string `json:"business_name"`
	Slug         string `json:"slug"`
	Name         string `json:"name"`
	Email        string `json:"email"`
	Password     string `json:"password"`
	Locale       string `json:"locale"`
	// TermsVersion é a versão dos termos que o usuário aceitou (ADR-008 §6).
	TermsVersion string `json:"terms_version"`
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

	if apiErr := checkTermsVersion(req.TermsVersion, h.termsVersion); apiErr != nil {
		writeError(w, *apiErr)
		return
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
		h.termsVersion, []string{domain.PurposeTerms},
	)
	if err != nil {
		h.logger.Error("signup_create_tenant_and_owner_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp, apiErr := h.issuer.Issue(ctx, user)
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

// Login autentica por e-mail+senha. Se a senha bater em contas de mais de um
// tenant e tenant_id não vier no corpo, devolve 409 multiple_tenants (ADR-002
// §2c) só com essas academias, para o cliente escolher e reenviar.
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
	if req.TenantID != "" {
		matches = filterTenant(matches, req.TenantID)
	}
	if len(matches) == 0 {
		// Mesmo custo de argon2 de um e-mail existente: o tempo de resposta
		// não pode dizer se o e-mail tem conta.
		burnPasswordCheck(req.Password)
		writeError(w, errInvalidCredentials())
		return
	}

	// A senha é conferida ANTES de qualquer resposta que dependa das contas
	// do e-mail: a lista de academias do 409 só sai para quem acertou a
	// senha de pelo menos uma delas (ADR-002 §2c) — senão qualquer um
	// descobriria onde um e-mail tem conta digitando uma senha qualquer.
	var authenticated []domain.User
	var options []tenantOption
	for _, m := range matches {
		user, err := h.users.FindByEmailInTenant(ctx, m.TenantID, req.Email)
		if err != nil {
			if err == repo.ErrNotFound {
				burnPasswordCheck(req.Password)
				continue
			}
			h.logger.Error("login_find_user_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		ok, err := security.VerifyPassword(req.Password, user.PasswordHash)
		if err != nil || !ok {
			continue
		}
		authenticated = append(authenticated, user)
		options = append(options, tenantOption{TenantID: m.TenantID, TenantName: m.TenantName})
	}

	switch len(authenticated) {
	case 0:
		writeError(w, errInvalidCredentials())
		return
	case 1:
		// Uma conta só com essa senha: entra direto, mesmo que o e-mail
		// exista em outras academias com outra senha.
	default:
		writeError(w, errMultipleTenants(options))
		return
	}
	user := authenticated[0]

	resp, apiErr := h.issuer.Issue(ctx, user)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// filterTenant mantém só a conta do tenant escolhido no 409.
func filterTenant(matches []domain.TenantMatch, tenantID string) []domain.TenantMatch {
	for _, m := range matches {
		if m.TenantID == tenantID {
			return []domain.TenantMatch{m}
		}
	}
	return nil
}

var (
	dummyHashOnce sync.Once
	dummyHash     string
)

// burnPasswordCheck gasta o mesmo argon2 de uma verificação real contra um
// hash descartável.
func burnPasswordCheck(password string) {
	dummyHashOnce.Do(func() {
		dummyHash, _ = security.HashPassword("lyfta-dummy-password")
	})
	if dummyHash != "" {
		_, _ = security.VerifyPassword(password, dummyHash)
	}
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

	// Conta em exclusão/excluída ou desativada não renova sessão (P4.5).
	if user.Status != domain.UserStatusActive {
		writeError(w, errInvalidToken())
		return
	}

	resp, apiErr := h.issuer.Issue(ctx, user)
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
