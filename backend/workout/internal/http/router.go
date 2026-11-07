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
func NewRouter(
	logger *slog.Logger,
	corsOrigins []string,
	verifier *security.JWTVerifier,
	internalToken string,
	mediaHandler *MediaHandler,
	exerciseHandler *ExerciseHandler,
	planHandler *PlanHandler,
	syncHandler *SyncHandler,
	historyHandler *HistoryHandler,
	pendingHandler *PendingStudentsHandler,
	erasureHandler *ErasureHandler,
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

	// M2M (ADR-013 §4/§5): o job diário do comms (P3.4) consulta quem tem
	// plano ativo e não treinou hoje. Autenticação própria (X-Internal-Token),
	// fora do /v1 porque não é uma requisição de usuário — não há JWT nem
	// tenant de request aqui, a consulta atravessa todos os tenants de
	// propósito (ver internal/repo.PendingRepo).
	r.Route("/internal/v1", func(r chi.Router) {
		r.Use(RequireInternalToken(internalToken))
		r.Get("/pending-students", pendingHandler.List)
		// Exclusão de conta (ADR-008 §2, P4.5): chamada pelo identity.
		r.Delete("/users/{id}", erasureHandler.EraseUser)
	})

	r.Route("/v1", func(r chi.Router) {
		r.Use(RequireAuth(verifier))
		// Sonda autenticada: confirma que o token do identity é aceito aqui e
		// devolve o tenant que o RLS vai aplicar nas rotas de negócio.
		r.Get("/whoami", whoamiHandler)

		// O plano ativo do aluno: resolvido pelo `sub` da claim, sem
		// parâmetro de aluno — nenhum token lê o plano de outra pessoa.
		r.Get("/me/plan", planHandler.MyPlan)

		// Execução e sync offline (P1.5, ADR-003). Não são rotas de
		// professor: quem empurra a fila é o device do aluno, e o aluno é
		// sempre o `sub` da claim. O coach entra só no override, e mesmo
		// assim mandando o student_id no corpo.
		r.Get("/me/today", syncHandler.Today)
		r.Post("/me/plan/override-day", syncHandler.OverrideDay)
		r.Post("/sync/workout-logs", syncHandler.PushLogs)
		r.Get("/sync/pull", syncHandler.Pull)

		// Agenda semanal do aluno (P4.1): sessões sincronizadas por período.
		// "Treino previsto" é projeção local da rotação no cliente, não uma
		// leitura de servidor.
		r.Get("/me/sessions", syncHandler.Sessions)

		// Progresso por exercício (P2.1). O eixo é o `exercise_id`, então a
		// série atravessa planos e versões; quem lê pelo `/me/` é sempre o
		// dono da claim.
		r.Get("/me/exercises/logged", historyHandler.MyLogged)
		r.Get("/me/exercises/{exercise_id}/history", historyHandler.MyHistory)

		// Biblioteca de exercícios: ler é de qualquer usuário autenticado (o
		// aluno vê nome e mídia no treino dele); escrever é do professor.
		r.Get("/exercises", exerciseHandler.List)
		r.Get("/exercises/{id}", exerciseHandler.Get)

		// Mídia de exercício: quem sobe GIF/vídeo é o professor (ADR-010 §3),
		// nunca o aluno.
		r.Group(func(r chi.Router) {
			r.Use(RequireRole("owner", "coach"))
			r.Post("/media/presign", mediaHandler.Presign)
			r.Post("/exercises", exerciseHandler.Create)
			r.Put("/exercises/{id}", exerciseHandler.Update)

			// Builder e atribuição (P1.4). Ler o plano é de qualquer
			// professor do tenant; escrever, só do coach dono ou do owner
			// (authorizeWrite).
			r.Post("/plans", planHandler.Create)
			r.Get("/plans/{id}", planHandler.Get)
			r.Put("/plans/{id}/draft", planHandler.UpdateDraft)
			r.Post("/plans/{id}/publish", planHandler.Publish)
			r.Get("/students/{id}/plans", planHandler.ListByStudent)

			// O mesmo progresso, com o aluno na URL: é o que a tela do
			// professor acompanha (P2.5).
			r.Get("/students/{id}/exercises/logged", historyHandler.StudentLogged)
			r.Get("/students/{id}/exercises/{exercise_id}/history", historyHandler.StudentHistory)
		})
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
