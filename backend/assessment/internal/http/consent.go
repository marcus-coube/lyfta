package http

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/security"
)

// PurposeProgressPhotos é a finalidade de consentimento das fotos de evolução
// (ADR-008 §1, P4.5) — mesmo valor emitido pelo identity.
const PurposeProgressPhotos = "progress_photos"

// ConsentChecker responde se um usuário consentiu numa finalidade. Serve para
// checar OUTRA pessoa (o coach agindo sobre as fotos de um aluno); para o
// próprio titular o assessment usa as claims do JWT, sem chamada síncrona.
type ConsentChecker interface {
	HasPurpose(ctx context.Context, tenantID, userID, purpose string) (bool, error)
}

// mineHasPhotoConsent: o aluno agindo sobre as próprias fotos.
func mineHasPhotoConsent(claims *security.Claims) bool {
	return claims.HasConsent(PurposeProgressPhotos)
}

// requireStudentPhotoConsent barra com 403 consent_required quando o aluno
// alvo não consentiu em fotos — vale para o coach lançando foto por ele. Falha
// ao consultar o identity é 500: na dúvida, não grava foto sem consentimento.
func requireStudentPhotoConsent(w http.ResponseWriter, r *http.Request, logger *slog.Logger, consents ConsentChecker, tenantID, studentID string) bool {
	consented, err := consents.HasPurpose(r.Context(), tenantID, studentID, PurposeProgressPhotos)
	if err != nil {
		logger.Error("photo_consent_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return false
	}
	if !consented {
		writeError(w, errConsentRequired(PurposeProgressPhotos))
		return false
	}
	return true
}

// RequireMyHealthData barra com 403 consent_required o titular sem a
// finalidade `health_data` na claim (ADR-008 §1): medidas, bioimpedância e
// anamnese são dado de saúde (P5.3).
func RequireMyHealthData(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, errUnauthenticated())
			return
		}
		if !claims.HasConsent(PurposeHealthData) {
			writeError(w, errConsentRequired(PurposeHealthData))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RequireStudentHealthData barra com 403 consent_required o coach agindo
// sobre dado de saúde de um aluno (`{id}` da rota) que não consentiu em
// `health_data`. Falha ao consultar o identity é 500: na dúvida, não expõe.
func RequireStudentHealthData(logger *slog.Logger, consents ConsentChecker) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tenantID, ok := TenantFromContext(r.Context())
			if !ok {
				writeError(w, errUnauthenticated())
				return
			}
			studentID := chi.URLParam(r, "id")
			if _, err := uuid.Parse(studentID); err != nil {
				writeError(w, errValidation("id"))
				return
			}
			consented, err := consents.HasPurpose(r.Context(), tenantID, studentID, PurposeHealthData)
			if err != nil {
				logger.Error("health_consent_check_failed", slog.Any("error", err))
				writeError(w, errInternal())
				return
			}
			if !consented {
				writeError(w, errConsentRequired(PurposeHealthData))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
