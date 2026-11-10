package http

import (
	"log/slog"
	"net/http"

	"github.com/getsentry/sentry-go"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// SentryScope dá a cada requisição um hub próprio (escopo isolado) com o
// request_id como tag. Vem logo depois de RequestID. Sem DSN o hub não tem
// cliente e tudo vira no-op.
func SentryScope(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hub := sentry.CurrentHub().Clone()
		hub.Scope().SetTag("request_id", RequestIDFromContext(r.Context()))
		next.ServeHTTP(w, r.WithContext(sentry.SetHubOnContext(r.Context(), hub)))
	})
}

// setSentryUser anota no escopo da requisição só user_id e tenant_id — nunca
// e-mail ou nome (ADR-008). Chamado por RequireAuth.
func setSentryUser(r *http.Request, userID, tenantID string) {
	if hub := sentry.GetHubFromContext(r.Context()); hub != nil {
		hub.Scope().SetUser(sentry.User{ID: userID})
		hub.Scope().SetTag("tenant_id", tenantID)
	}
}

// Recover captura panics e responde 500 sem derrubar o processo, logando o
// erro com o request-id e reportando ao Sentry (quando ligado).
func Recover(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rec := recover(); rec != nil {
					logger.Error("panic_recovered",
						slog.String("request_id", RequestIDFromContext(r.Context())),
						slog.Any("error", rec),
					)
					if hub := sentry.GetHubFromContext(r.Context()); hub != nil {
						hub.Recover(rec)
					}
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusInternalServerError)
					_, _ = w.Write([]byte(`{"code":"internal_error","params":{}}`))
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

// ReportServerErrors reporta respostas 5xx (as que não são panic — essas o
// Recover já reporta) com a rota e o request_id. Fica DENTRO do Recover: um
// panic passa direto por aqui. A causa detalhada está no log, correlacionável
// pelo request_id; o evento não carrega corpo nem query (ADR-008).
func ReportServerErrors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		if ww.Status() < 500 {
			return
		}
		hub := sentry.GetHubFromContext(r.Context())
		if hub == nil {
			return
		}
		route := r.URL.Path
		if rc := chi.RouteContext(r.Context()); rc != nil && rc.RoutePattern() != "" {
			route = rc.RoutePattern()
		}
		hub.WithScope(func(s *sentry.Scope) {
			s.SetFingerprint([]string{r.Method, route, http.StatusText(ww.Status())})
			hub.CaptureMessage("http " + http.StatusText(ww.Status()) + ": " + r.Method + " " + route)
		})
	})
}
