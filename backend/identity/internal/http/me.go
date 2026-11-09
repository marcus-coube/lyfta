package http

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// Eraser pede aos outros serviços que apaguem/anonimizem os dados de um
// usuário (ADR-008 §2). Devolve os nomes dos serviços que falharam; vazio =
// tudo apagado. Cada serviço é idempotente, então repetir é seguro.
type Eraser interface {
	Erase(ctx context.Context, tenantID, userID string) (failed []string)
}

// AccountHandler concentra os endpoints da conta do próprio usuário:
// consentimentos (ADR-008 §1) e exclusão de conta (ADR-008 §2), P4.5.
type AccountHandler struct {
	logger       *slog.Logger
	users        *repo.UserRepo
	auth         *repo.AuthRepo
	consents     *repo.ConsentRepo
	issuer       *SessionIssuer
	eraser       Eraser
	termsVersion string
}

// NewAccountHandler cria o handler da conta.
func NewAccountHandler(logger *slog.Logger, users *repo.UserRepo, auth *repo.AuthRepo, consents *repo.ConsentRepo, issuer *SessionIssuer, eraser Eraser, termsVersion string) *AccountHandler {
	return &AccountHandler{logger: logger, users: users, auth: auth, consents: consents, issuer: issuer, eraser: eraser, termsVersion: termsVersion}
}

type consentsResponse struct {
	TermsVersion string `json:"terms_version"`
	// Required são as finalidades sem as quais o papel do usuário não usa o
	// app; Granted são as vigentes na versão atual dos termos.
	Required     []string `json:"required"`
	Granted      []string `json:"granted"`
	NeedsConsent bool     `json:"needs_consent"`
	// AccessToken/ExpiresAt só vêm no PUT: um token novo com as claims
	// atualizadas, para a mudança valer nos outros serviços sem esperar o
	// access token antigo expirar.
	AccessToken string `json:"access_token,omitempty"`
	ExpiresAt   string `json:"expires_at,omitempty"`
}

// currentConsents monta o estado de consentimento do usuário da claim.
func (h *AccountHandler) currentConsents(ctx context.Context, claims *security.Claims) (consentsResponse, domain.User, error) {
	user, err := h.auth.FindUserByID(ctx, claims.TenantID, claims.Subject)
	if err != nil {
		return consentsResponse{}, domain.User{}, err
	}
	granted, needs, err := h.issuer.grantedPurposes(ctx, user)
	if err != nil {
		return consentsResponse{}, domain.User{}, err
	}
	return consentsResponse{
		TermsVersion: h.termsVersion,
		Required:     domain.RequiredPurposes(user.Roles),
		Granted:      granted,
		NeedsConsent: needs,
	}, user, nil
}

// GetConsents — GET /v1/me/consents.
func (h *AccountHandler) GetConsents(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	resp, _, err := h.currentConsents(r.Context(), claims)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errUnauthenticated())
			return
		}
		h.logger.Error("consents_get_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

type putConsentsRequest struct {
	TermsVersion string          `json:"terms_version"`
	Consents     map[string]bool `json:"consents"`
}

// PutConsents — PUT /v1/me/consents: concede (true) ou revoga (false) as
// finalidades informadas. Append-only: revogar grava revoked_at. Devolve o
// estado novo com um access token já refletindo a mudança.
func (h *AccountHandler) PutConsents(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	var req putConsentsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if apiErr := checkTermsVersion(req.TermsVersion, h.termsVersion); apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	for purpose := range req.Consents {
		if !domain.IsKnownPurpose(purpose) {
			writeError(w, errValidation("consents"))
			return
		}
	}

	ctx := r.Context()
	if err := h.consents.Apply(ctx, claims.TenantID, claims.Subject, h.termsVersion, req.Consents); err != nil {
		h.logger.Error("consents_put_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp, user, err := h.currentConsents(ctx, claims)
	if err != nil {
		h.logger.Error("consents_put_reload_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	roles := make([]string, 0, len(user.Roles))
	for _, role := range user.Roles {
		roles = append(roles, string(role))
	}
	timezone, err := h.issuer.tenantTimezone(ctx, user.TenantID)
	if err != nil {
		h.logger.Error("consents_put_tenant_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	access, expiresAt, err := h.issuer.jwt.Sign(user.ID, user.TenantID, roles, user.Locale, timezone, resp.Granted)
	if err != nil {
		h.logger.Error("consents_put_sign_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp.AccessToken = access
	resp.ExpiresAt = expiresAt.UTC().Format(time.RFC3339)
	writeJSON(w, http.StatusOK, resp)
}

type deleteAccountRequest struct {
	Password string `json:"password"`
}

// DeleteMe — DELETE /v1/me: exclusão de conta self-service (ADR-008 §2),
// confirmada por senha. Fluxo: marca `deleting` (login e refresh bloqueados) →
// pede a exclusão a cada serviço → anonimiza o usuário aqui. Falha num serviço
// = 502 `erasure_failed`; o usuário segue `deleting` e a chamada pode ser
// repetida enquanto o access token valer (nada é refeito em duplicidade: todo
// passo é idempotente).
//
// O owner não exclui a própria conta: encerrar o tenant é outro fluxo, fora do
// MVP.
func (h *AccountHandler) DeleteMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	for _, role := range claims.Roles {
		if role == string(domain.RoleOwner) {
			writeError(w, errOwnerCannotDelete())
			return
		}
	}

	var req deleteAccountRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if req.Password == "" {
		writeError(w, errInvalidPassword())
		return
	}

	ctx := r.Context()
	tenantID, userID := claims.TenantID, claims.Subject

	hash, err := h.users.PasswordHash(ctx, tenantID, userID)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errUnauthenticated())
			return
		}
		h.logger.Error("delete_me_hash_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if ok, err := security.VerifyPassword(req.Password, hash); err != nil || !ok {
		writeError(w, errInvalidPassword())
		return
	}

	if err := h.users.MarkDeleting(ctx, tenantID, userID); err != nil {
		h.logger.Error("delete_me_mark_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if failed := h.eraser.Erase(ctx, tenantID, userID); len(failed) > 0 {
		h.logger.Error("delete_me_erasure_failed", slog.Any("services", failed), slog.String("user_id", userID))
		writeError(w, errErasureFailed(failed))
		return
	}

	if err := h.users.Anonymize(ctx, tenantID, userID); err != nil {
		h.logger.Error("delete_me_anonymize_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type internalConsentsResponse struct {
	Purposes []string `json:"purposes"`
}

// InternalConsents — GET /internal/v1/users/{id}/consents?tenant_id=: as
// finalidades vigentes (versão atual dos termos) de um usuário, para um
// serviço checar o consentimento de OUTRA pessoa (ex.: o assessment, quando o
// coach lê as fotos de um aluno). As claims só cobrem quem faz a chamada.
func (h *AccountHandler) InternalConsents(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	tenantID := r.URL.Query().Get("tenant_id")
	if _, err := uuid.Parse(userID); err != nil {
		writeError(w, errValidation("id"))
		return
	}
	if _, err := uuid.Parse(tenantID); err != nil {
		writeError(w, errValidation("tenant_id"))
		return
	}
	purposes, err := h.consents.ActivePurposes(r.Context(), tenantID, userID, h.termsVersion)
	if err != nil {
		h.logger.Error("internal_consents_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	writeJSON(w, http.StatusOK, internalConsentsResponse{Purposes: purposes})
}
