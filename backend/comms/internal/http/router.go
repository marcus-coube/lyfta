package http

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"

	"github.com/marcus-coube/lyfta/comms/internal/security"
)

// NewRouter monta o roteador chi do serviço comms com os middlewares base
// (request-id, logging estruturado, recover, CORS).
//
// P3.2 acrescenta o chat: REST sob `/v1` (histórico é sempre por
// participante, sem porta `/me` × `/students/{id}` porque as duas pontas de
// uma conversa acessam o mesmo recurso) e `GET /ws` fora do `/v1` — o plano
// pede a rota nesse formato porque o token chega pela query string, não pelo
// header Authorization (o handshake de WS do browser não manda header
// customizado). StructuredLogging só loga `r.URL.Path`, que no `net/http` já
// exclui a query string — o token de `/ws?token=...` não aparece no log de
// requisição sem precisar de nenhuma redação extra (conferido aqui: ver
// middleware.go).
func NewRouter(
	logger *slog.Logger,
	corsOrigins []string,
	verifier *security.JWTVerifier,
	internalToken string,
	conversationHandler *ConversationHandler,
	mediaHandler *MediaHandler,
	wsHandler *WSHandler,
	checkinHandler *CheckinHandler,
	deviceHandler *DeviceHandler,
	erasureHandler *ErasureHandler,
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
	// Autenticação própria (token na query, ver WSHandler.Serve) — fora do
	// grupo /v1 porque não usa o Authorization header do RequireAuth.
	r.Get("/ws", wsHandler.Serve)

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

		// Aluno e coach acessam a mesma conversa pelas mesmas rotas — a
		// autorização é "sou participante desta conversa", checada dentro do
		// handler (loadParticipantConversation), não pela URL como no padrão
		// /me × /students/{id} do workout/assessment.
		r.Get("/conversations", conversationHandler.List)
		r.Get("/conversations/{id}/messages", conversationHandler.ListMessages)
		r.Post("/conversations/{id}/messages", conversationHandler.SendMessage)
		r.Post("/conversations/{id}/read", conversationHandler.MarkRead)
		r.Post("/conversations/{id}/media/presign", mediaHandler.Presign)

		// Só o coach abre uma conversa nova — "qualquer professor do tenant" é
		// o mesmo critério do P1.4/P2.1/P2.3.
		r.Group(func(r chi.Router) {
			r.Use(RequireRole("owner", "coach"))
			r.Post("/conversations", conversationHandler.Start)
		})

		// Check-in de treino (P3.3): o aluno escreve o próprio (student_id vem
		// da claim, ver CheckinHandler.Create) — sem restrição de papel aqui,
		// igual ao restante do chat. Ler a fila e revisar é coisa de
		// coach/owner, mesmo critério de "qualquer professor do tenant".
		r.Post("/checkins", checkinHandler.Create)
		r.Group(func(r chi.Router) {
			r.Use(RequireRole("owner", "coach"))
			r.Get("/checkins", checkinHandler.List)
			r.Post("/checkins/{id}/review", checkinHandler.Review)
		})

		// Registro de token de push (P3.4, passo 1) — qualquer usuário
		// autenticado registra o próprio device, sem restrição de papel.
		r.Post("/devices", deviceHandler.Register)
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
