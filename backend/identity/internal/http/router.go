package http

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"
)

// NewRouter monta o roteador chi do serviço identity com os middlewares base
// (request-id, logging estruturado, recover, CORS) e as rotas disponíveis.
func NewRouter(logger *slog.Logger, corsOrigins []string) http.Handler {
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

	return r
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
