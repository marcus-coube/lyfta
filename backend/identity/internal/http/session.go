package http

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"log/slog"
	"time"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// tokenResponse é o corpo devolvido por signup/login/refresh/accept
// bem-sucedidos. `consents`, `needs_consent` e `terms_version` (P4.5) deixam
// o app decidir pelo gate de consentimento sem decodificar o JWT.
type tokenResponse struct {
	AccessToken  string   `json:"access_token"`
	RefreshToken string   `json:"refresh_token"`
	ExpiresAt    string   `json:"expires_at"`
	TenantID     string   `json:"tenant_id"`
	UserID       string   `json:"user_id"`
	Roles        []string `json:"roles"`
	Consents     []string `json:"consents"`
	NeedsConsent bool     `json:"needs_consent"`
	TermsVersion string   `json:"terms_version"`
}

// SessionIssuer emite o par access+refresh para um usuário, com as
// finalidades de consentimento vigentes nas claims (ADR-008 §1). É usado por
// signup, login, refresh e aceite de convite.
type SessionIssuer struct {
	logger       *slog.Logger
	jwt          *security.JWTSigner
	auth         *repo.AuthRepo
	consents     *repo.ConsentRepo
	tenants      *repo.TenantRepo
	termsVersion string
}

// NewSessionIssuer cria o emissor de sessão.
func NewSessionIssuer(logger *slog.Logger, jwt *security.JWTSigner, auth *repo.AuthRepo, consents *repo.ConsentRepo, tenants *repo.TenantRepo, termsVersion string) *SessionIssuer {
	return &SessionIssuer{logger: logger, jwt: jwt, auth: auth, consents: consents, tenants: tenants, termsVersion: termsVersion}
}

// grantedPurposes devolve as finalidades vigentes do usuário na versão atual
// dos termos e se falta alguma obrigatória para o papel dele.
func (s *SessionIssuer) grantedPurposes(ctx context.Context, user domain.User) (granted []string, needsConsent bool, err error) {
	granted, err = s.consents.ActivePurposes(ctx, user.TenantID, user.ID, s.termsVersion)
	if err != nil {
		return nil, false, err
	}
	have := make(map[string]bool, len(granted))
	for _, p := range granted {
		have[p] = true
	}
	for _, p := range domain.RequiredPurposes(user.Roles) {
		if !have[p] {
			needsConsent = true
		}
	}
	return granted, needsConsent, nil
}

// tenantTimezone devolve o fuso do tenant para a claim `tz`.
func (s *SessionIssuer) tenantTimezone(ctx context.Context, tenantID string) (string, error) {
	t, err := s.tenants.FindByID(ctx, tenantID)
	if err != nil {
		return "", err
	}
	return t.Timezone, nil
}

// Issue assina um access token novo e cria um refresh token novo.
func (s *SessionIssuer) Issue(ctx context.Context, user domain.User) (tokenResponse, *APIError) {
	roles := make([]string, 0, len(user.Roles))
	for _, role := range user.Roles {
		roles = append(roles, string(role))
	}

	granted, needsConsent, err := s.grantedPurposes(ctx, user)
	if err != nil {
		s.logger.Error("issue_tokens_consents_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	timezone, err := s.tenantTimezone(ctx, user.TenantID)
	if err != nil {
		s.logger.Error("issue_tokens_tenant_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	access, expiresAt, err := s.jwt.Sign(user.ID, user.TenantID, roles, user.Locale, timezone, granted)
	if err != nil {
		s.logger.Error("issue_tokens_sign_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	refreshPlain, err := generateOpaqueToken()
	if err != nil {
		s.logger.Error("issue_tokens_refresh_gen_failed", slog.Any("error", err))
		errAPI := errInternal()
		return tokenResponse{}, &errAPI
	}

	if _, err := s.auth.CreateRefreshToken(ctx, user.TenantID, user.ID, repo.HashToken(refreshPlain), time.Now().Add(repo.RefreshTokenTTL)); err != nil {
		s.logger.Error("issue_tokens_create_refresh_failed", slog.Any("error", err))
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
		Consents:     granted,
		NeedsConsent: needsConsent,
		TermsVersion: s.termsVersion,
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

// checkTermsVersion confere a versão dos termos informada pelo cliente: vazia
// = não aceitou (400); diferente da vigente = aceitou um texto velho (409, o
// app recarrega os termos).
func checkTermsVersion(given, current string) *APIError {
	if given == "" {
		e := errConsentRequired(domain.PurposeTerms)
		return &e
	}
	if given != current {
		e := errTermsVersionMismatch(current)
		return &e
	}
	return nil
}
