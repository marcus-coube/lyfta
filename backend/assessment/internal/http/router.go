package http

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"

	"github.com/marcus-coube/lyfta/assessment/internal/security"
)

// NewRouter monta o roteador chi do serviço assessment com os middlewares
// base (request-id, logging estruturado, recover, CORS).
//
// API completa da P2.3: medidas, bioimpedância e fotos de evolução, cada uma
// com duas portas — `/me/...` para o aluno (resolvido pela claim, sem
// parâmetro de aluno na URL) e `/students/{id}/...` para o coach (owner ou
// professor vinculado ao aluno, ADR-016). O resumo do coach
// (`/students/{id}/summary`) e o presign de foto seguem o mesmo par de rotas.
func NewRouter(
	logger *slog.Logger,
	corsOrigins []string,
	verifier *security.JWTVerifier,
	internalToken string,
	measurementHandler *MeasurementHandler,
	bioimpedanceHandler *BioimpedanceHandler,
	photoHandler *PhotoHandler,
	mediaHandler *MediaHandler,
	summaryHandler *SummaryHandler,
	erasureHandler *ErasureHandler,
	profileHandler *ProfileHandler,
	linker StudentLinker,
	consents ConsentChecker,
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

	// M2M (ADR-013 §4/§5): exclusão de conta, chamada pelo identity (P4.5).
	r.Route("/internal/v1", func(r chi.Router) {
		r.Use(RequireInternalToken(internalToken))
		r.Delete("/users/{id}", erasureHandler.EraseUser)
	})

	r.Route("/v1", func(r chi.Router) {
		r.Use(RequireAuth(verifier))
		// Sonda autenticada: confirma que o token do identity é aceito aqui e
		// devolve o tenant que o RLS vai aplicar nas rotas de negócio.
		r.Get("/whoami", whoamiHandler)

		// O aluno é sempre o `sub` da claim: nenhuma destas rotas tem
		// parâmetro de aluno, então nenhum token lê/escreve o registro de
		// outra pessoa.
		r.Route("/me", func(r chi.Router) {
			// Dado de saúde (ADR-008 §1): medidas, bioimpedância e anamnese
			// exigem `health_data`; fotos têm finalidade própria.
			r.Group(func(r chi.Router) {
				r.Use(RequireMyHealthData)
				r.Post("/measurements", measurementHandler.CreateMine)
				r.Get("/measurements", measurementHandler.ListMine)
				r.Delete("/measurements/{measurement_id}", measurementHandler.DeleteMine)

				r.Post("/bioimpedance", bioimpedanceHandler.CreateMine)
				r.Get("/bioimpedance", bioimpedanceHandler.ListMine)
				r.Delete("/bioimpedance/{record_id}", bioimpedanceHandler.DeleteMine)

				r.Get("/profile", profileHandler.GetMine)
				r.Put("/profile", profileHandler.PutMine)
				r.Get("/injuries", profileHandler.ListMine)
				r.Post("/injuries", profileHandler.CreateInjuryMine)
				r.Patch("/injuries/{injury_id}", profileHandler.UpdateInjuryMine)
				r.Delete("/injuries/{injury_id}", profileHandler.DeleteInjuryMine)
			})

			r.Post("/photos", photoHandler.CreateMine)
			r.Get("/photos", photoHandler.ListMine)
			r.Delete("/photos/{photo_id}", photoHandler.DeleteMine)

			r.Post("/media/presign", mediaHandler.PresignMine)
		})

		// O coach lê e lança pelos seus alunos — é comum em avaliação
		// presencial. Só o owner ou o professor vinculado ao aluno passa
		// (ADR-016): o middleware roda antes do handler e, portanto, antes da
		// checagem de consentimento.
		r.Group(func(r chi.Router) {
			r.Use(RequireRole("owner", "coach"))

			r.Route("/students/{id}", func(r chi.Router) {
				r.Use(RequireStudentLink(logger, linker))

				r.Group(func(r chi.Router) {
					r.Use(RequireStudentHealthData(logger, consents))
					r.Post("/measurements", measurementHandler.CreateForStudent)
					r.Get("/measurements", measurementHandler.ListForStudent)
					r.Delete("/measurements/{measurement_id}", measurementHandler.DeleteForStudent)

					r.Post("/bioimpedance", bioimpedanceHandler.CreateForStudent)
					r.Get("/bioimpedance", bioimpedanceHandler.ListForStudent)
					r.Delete("/bioimpedance/{record_id}", bioimpedanceHandler.DeleteForStudent)

					r.Get("/profile", profileHandler.GetForStudent)
					r.Put("/profile", profileHandler.PutForStudent)
					r.Get("/injuries", profileHandler.ListForStudent)
					r.Post("/injuries", profileHandler.CreateInjuryForStudent)
					r.Patch("/injuries/{injury_id}", profileHandler.UpdateInjuryForStudent)
					r.Delete("/injuries/{injury_id}", profileHandler.DeleteInjuryForStudent)
				})

				r.Post("/photos", photoHandler.CreateForStudent)
				r.Get("/photos", photoHandler.ListForStudent)
				r.Delete("/photos/{photo_id}", photoHandler.DeleteForStudent)

				r.Post("/media/presign", mediaHandler.PresignForStudent)

				// O resumo mistura finalidades: cada bloco respeita a sua.
				r.Get("/summary", summaryHandler.Get)
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
