// Package http contém os handlers HTTP e middlewares do serviço workout.
package http

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/security"
)

type ctxKey string

const (
	ctxKeyRequestID ctxKey = "request_id"
	ctxKeyClaims    ctxKey = "auth_claims"
)

// RequestID injeta um UUID por requisição (header X-Request-Id, aceitando o
// valor recebido do cliente/proxy se já vier setado) e o expõe no contexto.
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

// RequireAuth valida o Bearer token com a chave pública do identity
// (ADR-013 §4) e injeta as claims no contexto.
//
// O tenant sai daqui pela claim e só dela: TenantFromContext é a única fonte
// aceita para `app.tenant_id` (repo.WithTenant). Body, query e header do
// cliente nunca decidem qual tenant o RLS vai aplicar.
func RequireAuth(verifier *security.JWTVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			const prefix = "Bearer "
			if !strings.HasPrefix(header, prefix) {
				writeError(w, errUnauthenticated())
				return
			}

			claims, err := verifier.Parse(strings.TrimPrefix(header, prefix))
			if err != nil {
				writeError(w, errUnauthenticated())
				return
			}
			// Token válido mas sem tenant não autoriza nada: sem tenant_id não
			// existe escopo de RLS para a requisição.
			if claims.TenantID == "" {
				writeError(w, errUnauthenticated())
				return
			}

			ctx := context.WithValue(r.Context(), ctxKeyClaims, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// ClaimsFromContext devolve as claims JWT da requisição autenticada atual.
func ClaimsFromContext(ctx context.Context) (*security.Claims, bool) {
	claims, ok := ctx.Value(ctxKeyClaims).(*security.Claims)
	return claims, ok
}

// TenantFromContext devolve o tenant_id da claim — o valor a passar para
// repo.WithTenant em todo acesso a dados.
func TenantFromContext(ctx context.Context) (string, bool) {
	claims, ok := ClaimsFromContext(ctx)
	if !ok || claims.TenantID == "" {
		return "", false
	}
	return claims.TenantID, true
}

// RequireRole exige que as claims contenham ao menos um dos papéis
// informados (ex.: biblioteca e builder são de owner|coach).
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

// Recover captura panics e responde 500 sem derrubar o processo.
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
