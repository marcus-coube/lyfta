package http

import (
	"context"
	"log/slog"
	"net/http"

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
