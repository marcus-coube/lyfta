package http

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/mail"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// InvitationHandler concentra as dependências dos endpoints de convite
// (P0.4): repositórios, o signer JWT (para o auto-login no accept) e o
// mailer (Resend em produção, log em dev/teste).
type InvitationHandler struct {
	logger      *slog.Logger
	invitations *repo.InvitationRepo
	users       *repo.UserRepo
	auth        *repo.AuthRepo
	jwt         *security.JWTSigner
	mailer      mail.Mailer
	appURL      string
}

// NewInvitationHandler cria um InvitationHandler com as dependências
// informadas.
func NewInvitationHandler(
	logger *slog.Logger,
	invitations *repo.InvitationRepo,
	users *repo.UserRepo,
	auth *repo.AuthRepo,
	jwt *security.JWTSigner,
	mailer mail.Mailer,
	appURL string,
) *InvitationHandler {
	return &InvitationHandler{
		logger:      logger,
		invitations: invitations,
		users:       users,
		auth:        auth,
		jwt:         jwt,
		mailer:      mailer,
		appURL:      appURL,
	}
}

// --- POST /v1/invitations (auth: owner|coach) ------------------------------

type createInvitationRequest struct {
	Email string `json:"email"`
	Role  string `json:"role"`
	// Name é opcional: o professor costuma saber o nome do aluno na hora de
	// convidar, e sem ele a lista de alunos (P1.6) mostraria e-mails. O
	// convidado pode corrigir depois no próprio perfil.
	Name string `json:"name"`
}

// Create cria um convite: usuário novo com status=invited + registro em
// invitations, e envia o e-mail com o link de aceite (plano P0.4 passo 2).
func (h *InvitationHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}

	var req createInvitationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.Role = strings.TrimSpace(req.Role)

	switch {
	case !strings.Contains(req.Email, "@"):
		writeError(w, errValidation("email"))
		return
	case req.Role != string(domain.RoleOwner) && req.Role != string(domain.RoleCoach) && req.Role != string(domain.RoleStudent):
		writeError(w, errValidation("role"))
		return
	case len(strings.TrimSpace(req.Name)) > maxInviteeNameLen:
		writeError(w, errValidation("name"))
		return
	}

	ctx := r.Context()
	tenantID := claims.TenantID

	if _, err := h.users.FindByEmailInTenant(ctx, tenantID, req.Email); err == nil {
		writeError(w, errEmailTaken())
		return
	} else if err != repo.ErrNotFound {
		h.logger.Error("invitation_check_email_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	user, err := h.users.Create(ctx, domain.User{
		TenantID: tenantID,
		Email:    req.Email,
		// Sem senha até o accept — hash vazio nunca casa com VerifyPassword
		// (formato esperado é `$argon2id$...`), então login continua
		// impossível antes do convite ser aceito.
		PasswordHash: "",
		Name:         inviteeName(req),
		Locale:       "pt-BR",
		Status:       domain.UserStatusInvited,
		Roles:        []domain.Role{domain.Role(req.Role)},
	})
	if err != nil {
		h.logger.Error("invitation_create_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	inv, apiErr := h.createAndSendInvitation(ctx, tenantID, user.Email, domain.Role(req.Role), claims.Subject)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	writeJSON(w, http.StatusCreated, invitationResponse{
		ID:        inv.ID,
		Email:     inv.Email,
		Role:      string(inv.Role),
		ExpiresAt: inv.ExpiresAt.UTC().Format(time.RFC3339),
	})
}

// maxInviteeNameLen limita o nome do convidado — a coluna é TEXT, a API não
// deve ser.
const maxInviteeNameLen = 120

// inviteeName usa o nome informado pelo professor e cai no e-mail quando ele
// não vem — o campo é opcional e a coluna `name` é NOT NULL.
func inviteeName(req createInvitationRequest) string {
	if name := strings.TrimSpace(req.Name); name != "" {
		return name
	}
	return req.Email
}

type invitationResponse struct {
	ID        string `json:"id"`
	Email     string `json:"email"`
	Role      string `json:"role"`
	ExpiresAt string `json:"expires_at"`
}

// createAndSendInvitation gera o token opaco, grava o convite (hash em
// banco) e envia o e-mail — compartilhado entre Create e Resend.
func (h *InvitationHandler) createAndSendInvitation(ctx context.Context, tenantID, email string, role domain.Role, invitedBy string) (domain.Invitation, *APIError) {
	tokenPlain, err := generateOpaqueToken()
	if err != nil {
		h.logger.Error("invitation_gen_token_failed", slog.Any("error", err))
		errAPI := errInternal()
		return domain.Invitation{}, &errAPI
	}

	// tenantName só é usada no corpo do e-mail; buscamos via find_tenants_by_email
	// seria excessivo aqui, então usamos o e-mail como identificação simples do
	// convite — suficiente para o template pt-BR do plano (não é dado sensível).
	inv, err := h.invitations.Create(ctx, domain.Invitation{
		TenantID:  tenantID,
		Email:     email,
		Role:      role,
		TokenHash: repo.HashToken(tokenPlain),
		InvitedBy: invitedBy,
		ExpiresAt: time.Now().Add(repo.InvitationTTL),
	})
	if err != nil {
		h.logger.Error("invitation_create_failed", slog.Any("error", err))
		errAPI := errInternal()
		return domain.Invitation{}, &errAPI
	}

	msg := mail.InvitationMessage(email, h.appURL, tokenPlain, "Lyfta")
	if err := h.mailer.Send(ctx, msg); err != nil {
		h.logger.Error("invitation_send_mail_failed", slog.Any("error", err))
		// Não falha a criação do convite por erro de e-mail (fica pendente de
		// reenvio) — mas registra o erro para investigação.
	}

	return inv, nil
}

// --- POST /v1/invitations/accept (público) ---------------------------------

type acceptInvitationRequest struct {
	Token    string `json:"token"`
	Password string `json:"password"`
}

// Accept ativa a conta do convidado: valida o token (existe, não expirado,
// não usado), define a senha, marca accepted_at e devolve tokens de sessão
// (auto-login) — plano P0.4 passo 3.
func (h *InvitationHandler) Accept(w http.ResponseWriter, r *http.Request) {
	var req acceptInvitationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if req.Token == "" {
		writeError(w, errInvalidToken())
		return
	}
	if len(req.Password) < 8 {
		writeError(w, errValidation("password"))
		return
	}

	ctx := r.Context()
	tokenHash := repo.HashToken(req.Token)

	inv, err := h.invitations.FindValidByTokenHash(ctx, tokenHash)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidToken())
			return
		}
		h.logger.Error("invitation_accept_find_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	user, err := h.users.FindByEmailInTenant(ctx, inv.TenantID, inv.Email)
	if err != nil {
		h.logger.Error("invitation_accept_find_user_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	passwordHash, err := security.HashPassword(req.Password)
	if err != nil {
		h.logger.Error("invitation_accept_hash_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if err := h.users.ActivateWithPassword(ctx, inv.TenantID, user.ID, passwordHash); err != nil {
		h.logger.Error("invitation_accept_activate_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if err := h.invitations.MarkAccepted(ctx, inv.TenantID, inv.ID); err != nil {
		h.logger.Error("invitation_accept_mark_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	user.Status = domain.UserStatusActive
	resp, apiErr := issueTokens(ctx, h.jwt, h.auth, h.logger, user)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// --- POST /v1/invitations/{id}/resend (auth: owner|coach) ------------------

// Resend invalida o token de convite anterior e cria+envia um novo (plano
// P0.4 passo 5).
func (h *InvitationHandler) Resend(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}

	id := chi.URLParam(r, "id")
	ctx := r.Context()
	tenantID := claims.TenantID

	inv, err := h.invitations.FindByID(ctx, tenantID, id)
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidToken())
			return
		}
		h.logger.Error("invitation_resend_find_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if inv.AcceptedAt != nil {
		writeError(w, errInvalidToken())
		return
	}

	if err := h.invitations.Invalidate(ctx, tenantID, inv.ID); err != nil {
		h.logger.Error("invitation_resend_invalidate_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	newInv, apiErr := h.createAndSendInvitation(ctx, tenantID, inv.Email, inv.Role, claims.Subject)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	writeJSON(w, http.StatusCreated, invitationResponse{
		ID:        newInv.ID,
		Email:     newInv.Email,
		Role:      string(newInv.Role),
		ExpiresAt: newInv.ExpiresAt.UTC().Format(time.RFC3339),
	})
}
