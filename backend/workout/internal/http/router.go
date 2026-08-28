package http

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"

	"github.com/marcus-coube/lyfta/workout/internal/security"
)

// NewRouter monta o roteador chi do serviço workout com os middlewares base
// (request-id, logging estruturado, recover, CORS).
//
// As rotas de negócio chegam nas tarefas seguintes: mídia (P1.2), biblioteca
// (P1.3), builder/atribuição (P1.4) e execução/sync (P1.5). O grupo
// autenticado já existe aqui para que elas nasçam atrás de RequireAuth.
func NewRouter(logger *slog.Logger, corsOrigins []string, verifier *security.JWTVerifier) http.Handler {
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
		r.Use(RequireAuth(verifier))
		// Sonda autenticada: confirma que o token do identity é aceito aqui e
		// devolve o tenant que o RLS vai aplicar nas rotas de negócio.
		r.Get("/whoami", whoamiHandler)
	})

	return r
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func whoamiHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"user_id":   claims.Subject,
		"tenant_id": claims.TenantID,
		"roles":     claims.Roles,
	})
}
