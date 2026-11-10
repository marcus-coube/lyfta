package http

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// NewRouter monta o roteador chi do serviço identity com os middlewares base
// (request-id, logging estruturado, recover, CORS) e as rotas disponíveis.
func NewRouter(
	logger *slog.Logger,
	corsOrigins []string,
	signer *security.JWTSigner,
	internalToken string,
	auth *AuthHandler,
	invitations *InvitationHandler,
	passwordReset *PasswordResetHandler,
	users *UserHandler,
	account *AccountHandler,
	tenant *TenantHandler,
	students *StudentHandler,
	limiter *RateLimiter,
) http.Handler {
	r := chi.NewRouter()

	r.Use(RequestID)
	r.Use(SentryScope)
	r.Use(StructuredLogging(logger))
	r.Use(Recover(logger))
	r.Use(ReportServerErrors)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   corsOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Content-Type", "Authorization", "X-Internal-Token", "X-Request-Id"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", healthzHandler)

	// M2M (ADR-013 §4/§5): outros serviços consultam o consentimento de um
	// usuário que não é quem faz a requisição (P4.5).
	r.Route("/internal/v1", func(r chi.Router) {
		r.Use(RequireInternalToken(internalToken))
		r.Get("/users/{id}/consents", account.InternalConsents)
		// Vínculo professor↔aluno (ADR-016 §3, P4.7).
		r.Get("/coaches/{id}/students", users.InternalCoachStudents)
		r.Get("/students/{id}/coach", users.InternalStudentCoach)
		// Fuso e configurações do tenant (P5.1): jobs que varrem tenants.
		r.Get("/tenants", tenant.InternalList)
		r.Get("/tenants/{id}", tenant.InternalGet)
		// Status dos alunos em lote (P5.2): jobs ignoram inativos.
		r.Post("/students/statuses", students.InternalStudentStatuses)
	})

	r.Route("/v1", func(r chi.Router) {
		// Endpoints públicos com limite de tentativas (ADR-002 §2c): cooldown
		// de RateLimitCooldown por IP e, onde há e-mail no corpo, por e-mail.
		r.With(limiter.middleware(ruleSignup)).Post("/tenants", auth.Signup)
		r.Route("/auth", func(r chi.Router) {
			r.With(limiter.middleware(ruleLogin)).Post("/login", auth.Login)
			r.Post("/refresh", auth.Refresh)
			r.Post("/logout", auth.Logout)
			r.With(limiter.middleware(ruleForgotPassword)).Post("/forgot-password", passwordReset.ForgotPassword)
			r.With(limiter.middleware(ruleResetPassword)).Post("/reset-password", passwordReset.ResetPassword)
		})
		// Conta do próprio usuário (P4.5): consentimentos (ADR-008 §1) e
		// exclusão de conta (ADR-008 §2). Qualquer papel autenticado.
		r.Route("/me", func(r chi.Router) {
			r.Use(RequireAuth(signer))
			r.Get("/consents", account.GetConsents)
			r.Put("/consents", account.PutConsents)
			r.Get("/", account.GetMe)
			r.Patch("/", account.PatchMe)
			r.Delete("/", account.DeleteMe)
		})

		// Usuários do tenant (P1.6): a lista de alunos do professor. É do
		// identity porque o vínculo aluno↔tenant vive aqui — nenhum serviço
		// lê o banco do outro (ADR-013 §2).
		// O aluno entra só para o diretório da equipe (nome do professor no
		// chat); o handler barra o resto (ver UserHandler.List).
		r.Route("/users", func(r chi.Router) {
			r.Use(RequireAuth(signer))
			r.Use(RequireRole(string(domain.RoleOwner), string(domain.RoleCoach), string(domain.RoleStudent)))
			r.Get("/", users.List)
			r.Get("/directory", users.Directory)
		})

		// Configurações do tenant (P5.1): todo papel lê, só o owner escreve.
		r.Route("/tenant", func(r chi.Router) {
			r.Use(RequireAuth(signer))
			r.Get("/", tenant.Get)
			r.With(RequireRole(string(domain.RoleOwner))).Put("/", tenant.Put)
		})

		// Alunos (P5.2): owner vê todos, coach só os vinculados a ele
		// (ADR-016; o handler responde 404 nos outros). Reatribuir o
		// professor é só do owner (ADR-016 §1).
		r.Route("/students", func(r chi.Router) {
			r.Use(RequireAuth(signer))
			r.Use(RequireRole(string(domain.RoleOwner), string(domain.RoleCoach)))
			r.Get("/", students.List)
			r.Get("/{id}", students.Get)
			r.Patch("/{id}", students.Patch)
			r.Post("/{id}/deactivate", students.Deactivate)
			r.Post("/{id}/reactivate", students.Reactivate)
			r.Get("/{id}/status-history", students.StatusHistory)
			r.With(RequireRole(string(domain.RoleOwner))).Put("/{id}/coach", users.PutStudentCoach)
		})

		r.Route("/invitations", func(r chi.Router) {
			// Aceite é público: o convidado só tem o token, ainda não tem sessão.
			r.With(limiter.middleware(ruleAcceptInvite)).Post("/accept", invitations.Accept)

			// Criar e reenviar convite exigem sessão de owner|coach.
			r.Group(func(r chi.Router) {
				r.Use(RequireAuth(signer))
				r.Use(RequireRole(string(domain.RoleOwner), string(domain.RoleCoach)))
				r.Post("/", invitations.Create)
				r.Post("/{id}/resend", invitations.Resend)
			})
		})
	})

	return r
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
