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
	auth *AuthHandler,
	invitations *InvitationHandler,
	passwordReset *PasswordResetHandler,
) http.Handler {
	r := chi.NewRouter()

	r.Use(RequestID)
	r.Use(StructuredLogging(logger))
	r.Use(Recover(logger))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   corsOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Content-Type", "Authorization", "X-Internal-Token", "X-Request-Id"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", healthzHandler)

	r.Route("/v1", func(r chi.Router) {
		r.Post("/tenants", auth.Signup)
		r.Route("/auth", func(r chi.Router) {
			r.Post("/login", auth.Login)
			r.Post("/refresh", auth.Refresh)
			r.Post("/logout", auth.Logout)
			r.Post("/forgot-password", passwordReset.ForgotPassword)
			r.Post("/reset-password", passwordReset.ResetPassword)
		})
		r.Route("/invitations", func(r chi.Router) {
			// Aceite é público: o convidado só tem o token, ainda não tem sessão.
			r.Post("/accept", invitations.Accept)

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
