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
	overviewHandler *OverviewHandler,
	linker StudentLinker,
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

	// M2M (ADR-013 §4/§5): o job diário do comms (P3.4) consulta quem tem
	// plano ativo e não treinou hoje. Autenticação própria (X-Internal-Token),
	// fora do /v1 porque não é uma requisição de usuário — não há JWT nem
	// tenant de request aqui: o comms manda a lista de tenants (`tenant_id`)
	// de cada fuso (P5.1, ver internal/repo.PendingRepo).
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

			// Builder e atribuição (P1.4). Só o owner ou o coach vinculado ao
			// aluno do plano lê e escreve (ADR-016 §4): as rotas por plano
			// checam `plan.StudentID` dentro do handler.
			r.Post("/plans", planHandler.Create)
			r.Get("/plans/{id}", planHandler.Get)
			r.Put("/plans/{id}/draft", planHandler.UpdateDraft)
			r.Post("/plans/{id}/publish", planHandler.Publish)
			r.Post("/plans/{id}/save-as-template", planHandler.SaveAsTemplate)

			// Ciclo de vida do plano do aluno (P6.2).
			r.Post("/plans/{id}/duplicate", planHandler.Duplicate)
			r.Post("/plans/{id}/archive", planHandler.Archive)
			r.Get("/plans/{id}/versions", planHandler.Versions)

			// Modelos de treino (ADR-018, P6.1): do tenant — qualquer coach
			// lista e aplica; editar e arquivar é do autor ou do owner. Ler e
			// editar a árvore reusa /plans/{id}.
			r.Get("/templates", planHandler.ListTemplates)
			r.Post("/templates", planHandler.CreateTemplate)
			r.Post("/templates/{id}/archive", planHandler.ArchiveTemplate)
			r.Post("/templates/{id}/unarchive", planHandler.UnarchiveTemplate)
			r.Post("/templates/{id}/assign", planHandler.AssignTemplate)
			r.Get("/templates/{id}/recipients", planHandler.ListRecipients)
			r.Post("/templates/{id}/reapply", planHandler.ReapplyTemplate)

			// Resumo em lote (último treino + plano ativo) da página de
			// alunos; o vínculo é filtrado id a id no handler.
			r.Post("/students/overview", overviewHandler.Students)

			// Rotas com o aluno na URL: o vínculo é checado antes do handler.
			r.Route("/students/{id}", func(r chi.Router) {
				r.Use(RequireStudentLink(logger, linker))
				r.Get("/plans", planHandler.ListByStudent)
				r.Post("/plans/{plan_id}/activate", planHandler.Activate)
				r.Put("/plan/next-day", planHandler.SetNextDay)
				// O mesmo progresso, com o aluno na URL: é o que a tela do
				// professor acompanha (P2.5).
				r.Get("/exercises/logged", historyHandler.StudentLogged)
				r.Get("/exercises/{exercise_id}/history", historyHandler.StudentHistory)
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
