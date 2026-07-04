// Package http contém os handlers HTTP e middlewares do serviço identity.
package http

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/identity/internal/security"
)

// ctxKeyRequestID identifica o valor do request-id no contexto da requisição.
type ctxKey string

const (
	ctxKeyRequestID ctxKey = "request_id"
	ctxKeyClaims    ctxKey = "auth_claims"
)

// RequestID injeta um UUID v4 por requisição (header X-Request-Id, aceitando
// o valor recebido do cliente/proxy se já vier setado) e o expõe no contexto.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if id == "" {
			id = uuid.NewString()
		}
		w.Header().Set("X-Request-Id", id)
		ctx := context.WithValue(r.Context(), ctxKeyRequestID, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequestIDFromContext devolve o request-id da requisição atual, se houver.
func RequestIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(ctxKeyRequestID).(string); ok {
		return v
	}
	return ""
}

// StructuredLogging loga cada requisição em JSON (slog) com método, rota,
// status, duração e request-id.
func StructuredLogging(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

			next.ServeHTTP(ww, r)

			logger.Info("http_request",
				slog.String("request_id", RequestIDFromContext(r.Context())),
				slog.String("method", r.Method),
				slog.String("path", r.URL.Path),
				slog.Int("status", ww.Status()),
				slog.Duration("duration", time.Since(start)),
			)
		})
	}
}

// RequireAuth é o primeiro middleware de autenticação do serviço (P0.4):
// extrai o Bearer token do header Authorization, valida com
// security.JWTSigner.Parse e injeta as claims no contexto da requisição.
// Não seta app.tenant_id sozinho — cada repo continua abrindo sua própria
// transação via WithTenant a partir do tenant_id da claim (nunca do
// body/query), para não confiar em input do cliente na hora de aplicar RLS.
func RequireAuth(signer *security.JWTSigner) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			const prefix = "Bearer "
			if !strings.HasPrefix(header, prefix) {
				writeError(w, errUnauthenticated())
				return
			}
			token := strings.TrimPrefix(header, prefix)

			claims, err := signer.Parse(token)
			if err != nil {
				writeError(w, errUnauthenticated())
				return
			}

			ctx := context.WithValue(r.Context(), ctxKeyClaims, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// ClaimsFromContext devolve as claims JWT da requisição autenticada atual,
// se RequireAuth já tiver rodado.
func ClaimsFromContext(ctx context.Context) (*security.Claims, bool) {
	claims, ok := ctx.Value(ctxKeyClaims).(*security.Claims)
	return claims, ok
}

// RequireRole exige que as claims da requisição (injetadas por RequireAuth)
// contenham ao menos um dos papéis informados — usado nos endpoints de
// convite, restritos a owner|coach.
func RequireRole(roles ...string) func(http.Handler) http.Handler {
	allowed := make(map[string]struct{}, len(roles))
	for _, r := range roles {
		allowed[r] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFromContext(r.Context())
			if !ok {
				writeError(w, errUnauthenticated())
				return
			}
			for _, role := range claims.Roles {
				if _, match := allowed[role]; match {
					next.ServeHTTP(w, r)
					return
				}
			}
			writeError(w, errForbidden())
		})
	}
}

// Recover captura panics e responde 500 sem derrubar o processo, logando o
// erro com o request-id da requisição.
func Recover(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rec := recover(); rec != nil {
					logger.Error("panic_recovered",
						slog.String("request_id", RequestIDFromContext(r.Context())),
						slog.Any("error", rec),
					)
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusInternalServerError)
					_, _ = w.Write([]byte(`{"code":"internal_error","params":{}}`))
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}
