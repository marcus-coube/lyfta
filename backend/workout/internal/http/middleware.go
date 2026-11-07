// Package http contém os handlers HTTP e middlewares do serviço workout.
package http

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
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

			setSentryUser(r, claims.Subject, claims.TenantID)
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

// RequireInternalToken protege rotas M2M (ADR-013 §4) — comparação simples
// do header X-Internal-Token com o valor configurado (env INTERNAL_TOKEN).
// Sem Bearer/claims aqui: quem chama é outro serviço (o comms, no caso do
// job diário da P3.4), não um usuário, então não existe tenant de request
// para setar — o handler que fica atrás desta rota consulta todos os
// tenants de propósito (ver internal/repo.PendingRepo).
func RequireInternalToken(token string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if token == "" || r.Header.Get("X-Internal-Token") != token {
				writeError(w, errUnauthenticated())
				return
			}
			next.ServeHTTP(w, r)
		})
	}
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

// StudentLinker responde se o ator pode acessar dados de um aluno
// (ADR-016): owner sempre; coach só o aluno vinculado a ele.
type StudentLinker interface {
	CanAccessStudent(ctx context.Context, tenantID, userID string, roles []string, studentID string) (bool, error)
}

// checkStudentLink aplica o vínculo. Devolve nil quando o acesso é permitido;
// senão o erro a responder: 404 `student_not_found` (indistinguível de aluno
// inexistente) ou 500 se o identity falhar — o acesso fecha (ADR-016 §3).
func checkStudentLink(ctx context.Context, logger *slog.Logger, linker StudentLinker, claims *security.Claims, studentID string) *APIError {
	ok, err := linker.CanAccessStudent(ctx, claims.TenantID, claims.Subject, claims.Roles, studentID)
	if err != nil {
		logger.Error("coach_link_check_failed", slog.Any("error", err))
		apiErr := errInternal()
		return &apiErr
	}
	if !ok {
		apiErr := errStudentNotFound()
		return &apiErr
	}
	return nil
}

// RequireStudentLink protege as rotas `/students/{id}/...`: o aluno da URL
// precisa ser do coach (ou o ator ser owner). Roda depois de RequireAuth.
func RequireStudentLink(logger *slog.Logger, linker StudentLinker) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFromContext(r.Context())
			if !ok {
				writeError(w, errUnauthenticated())
				return
			}
			if apiErr := checkStudentLink(r.Context(), logger, linker, claims, chi.URLParam(r, "id")); apiErr != nil {
				writeError(w, *apiErr)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
