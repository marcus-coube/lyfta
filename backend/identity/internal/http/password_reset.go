package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/mail"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// PasswordResetHandler concentra os endpoints públicos de recuperação de
// senha (P0.4 passo 4): forgot-password (dispara o e-mail) e reset-password
// (consome o token e troca a senha).
type PasswordResetHandler struct {
	logger *slog.Logger
	auth   *repo.AuthRepo
	users  *repo.UserRepo
	resets *repo.PasswordResetRepo
	mailer mail.Mailer
	appURL string
}

// NewPasswordResetHandler cria um PasswordResetHandler com as dependências
// informadas.
func NewPasswordResetHandler(
	logger *slog.Logger,
	auth *repo.AuthRepo,
	users *repo.UserRepo,
	resets *repo.PasswordResetRepo,
	mailer mail.Mailer,
	appURL string,
) *PasswordResetHandler {
	return &PasswordResetHandler{
		logger: logger,
		auth:   auth,
		users:  users,
		resets: resets,
		mailer: mailer,
		appURL: appURL,
	}
}

// --- POST /v1/auth/forgot-password (público) -------------------------------

type forgotPasswordRequest struct {
	Email string `json:"email"`
}

// ForgotPassword dispara o e-mail de recuperação. Responde SEMPRE 200
// (mesmo sem conta com o e-mail) para não vazar quais e-mails estão
// cadastrados — o cliente nunca distingue os dois casos.
//
// O e-mail pode existir em mais de um tenant (ADR-002: conta por tenant);
// nesse caso criamos um pedido de reset e enviamos um e-mail por conta ativa.
func (h *PasswordResetHandler) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var req forgotPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))

	// E-mail sintaticamente inválido: nada a fazer, mas ainda respondemos 200
	// para não servir de oráculo de existência.
	if strings.Contains(email, "@") {
		matches, err := h.auth.FindTenantsByEmail(r.Context(), email)
		if err != nil {
			h.logger.Error("forgot_password_lookup_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
		for _, m := range matches {
			h.sendReset(r, m.TenantID, m.UserID, email)
		}
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{})
}

// sendReset gera o token opaco, grava o pedido (hash em banco) e envia o
// e-mail. Erros são logados mas não interrompem o fluxo — a resposta ao
// cliente é sempre 200, independentemente do que aconteça aqui.
func (h *PasswordResetHandler) sendReset(r *http.Request, tenantID, userID, email string) {
	ctx := r.Context()
	tokenPlain, err := generateOpaqueToken()
	if err != nil {
		h.logger.Error("forgot_password_gen_token_failed", slog.Any("error", err))
		return
	}

	if _, err := h.resets.Create(ctx, domain.PasswordReset{
		TenantID:  tenantID,
		UserID:    userID,
		TokenHash: repo.HashToken(tokenPlain),
		ExpiresAt: time.Now().Add(repo.PasswordResetTTL),
	}); err != nil {
		h.logger.Error("forgot_password_create_failed", slog.Any("error", err))
		return
	}

	msg := mail.PasswordResetMessage(email, h.appURL, tokenPlain)
	if err := h.mailer.Send(ctx, msg); err != nil {
		h.logger.Error("forgot_password_send_mail_failed", slog.Any("error", err))
	}
}

// --- POST /v1/auth/reset-password (público) --------------------------------

type resetPasswordRequest struct {
	Token    string `json:"token"`
	Password string `json:"password"`
}

// ResetPassword consome o token de recuperação (válido, não expirado, não
// usado), troca a senha (argon2id) e marca o pedido como usado (uso único).
func (h *PasswordResetHandler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req resetPasswordRequest
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
	pr, err := h.resets.FindValidByTokenHash(ctx, repo.HashToken(req.Token))
	if err != nil {
		if err == repo.ErrNotFound {
			writeError(w, errInvalidToken())
			return
		}
		h.logger.Error("reset_password_find_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	passwordHash, err := security.HashPassword(req.Password)
	if err != nil {
		h.logger.Error("reset_password_hash_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	if err := h.users.UpdatePassword(ctx, pr.TenantID, pr.UserID, passwordHash); err != nil {
		h.logger.Error("reset_password_update_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if err := h.resets.MarkUsed(ctx, pr.TenantID, pr.ID); err != nil {
		h.logger.Error("reset_password_mark_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
