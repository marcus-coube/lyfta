package http

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// SummaryHandler é o resumo do aluno que o coach vê na ficha (P2.3): última
// medida, última bioimpedância, contagem de fotos, deltas vs o registro
// anterior, objetivo e lesões ativas. Só o coach lê — a tela do aluno já tem as três listas completas,
// não precisa de um resumo condensado.
type SummaryHandler struct {
	logger       *slog.Logger
	measurements *repo.MeasurementRepo
	bioimpedance *repo.BioimpedanceRepo
	photos       *repo.PhotoRepo
	profiles     *repo.ProfileRepo
	injuries     *repo.InjuryRepo
	consents     ConsentChecker
}

// NewSummaryHandler cria o handler de resumo.
func NewSummaryHandler(logger *slog.Logger, measurements *repo.MeasurementRepo, bioimpedance *repo.BioimpedanceRepo, photos *repo.PhotoRepo, profiles *repo.ProfileRepo, injuries *repo.InjuryRepo, consents ConsentChecker) *SummaryHandler {
	return &SummaryHandler{logger: logger, measurements: measurements, bioimpedance: bioimpedance, photos: photos, profiles: profiles, injuries: injuries, consents: consents}
}

type summaryDeltaDTO struct {
	WeightKg   *float64 `json:"weight_kg"`
	BodyFatPct *float64 `json:"body_fat_pct"`
	WaistCm    *float64 `json:"waist_cm"`
}

type summaryResponse struct {
	LatestMeasurement  *measurementDTO  `json:"latest_measurement"`
	LatestBioimpedance *bioimpedanceDTO `json:"latest_bioimpedance"`
	PhotoCount         int              `json:"photo_count"`
	Deltas             summaryDeltaDTO  `json:"deltas"`
	// Anamnese (P5.3): objetivo e lesões ativas. Sem consentimento de saúde:
	// medidas/bioimpedância nulas, deltas nulos, goal nulo e lista vazia.
	Goal           *string     `json:"goal"`
	ActiveInjuries []injuryDTO `json:"active_injuries"`
}

// Get monta o resumo do aluno informado na URL.
func (h *SummaryHandler) Get(w http.ResponseWriter, r *http.Request) {
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

	// Sem consentimento em fotos o coach não vê nem a contagem (ADR-008 §1).
	consented, err := h.consents.HasPurpose(r.Context(), tenantID, studentID, PurposeProgressPhotos)
	if err != nil {
		h.logger.Error("summary_consent_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	photoCount := 0
	if consented {
		photoCount, err = h.photos.Count(r.Context(), tenantID, studentID)
		if err != nil {
			h.logger.Error("summary_photos_failed", slog.Any("error", err))
			writeError(w, errInternal())
			return
		}
	}

	resp := summaryResponse{PhotoCount: photoCount, ActiveInjuries: []injuryDTO{}}
	// Sem consentimento de saúde o coach não vê medidas, bioimpedância nem
	// anamnese (ADR-008 §1): os blocos vêm nulos/vazios.
	healthOK, err := h.consents.HasPurpose(r.Context(), tenantID, studentID, PurposeHealthData)
	if err != nil {
		h.logger.Error("summary_consent_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	if !healthOK {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	measurements, _, err := h.measurements.List(r.Context(), tenantID, studentID, nil, "", 2)
	if err != nil {
		h.logger.Error("summary_measurements_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	bio, _, err := h.bioimpedance.List(r.Context(), tenantID, studentID, nil, "", 2)
	if err != nil {
		h.logger.Error("summary_bioimpedance_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	profile, err := h.profiles.Get(r.Context(), tenantID, studentID)
	if err != nil && !errors.Is(err, repo.ErrNotFound) {
		h.logger.Error("summary_profile_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp.Goal = profile.Goal
	injuries, err := h.injuries.List(r.Context(), tenantID, studentID, true)
	if err != nil {
		h.logger.Error("summary_injuries_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	for _, in := range injuries {
		resp.ActiveInjuries = append(resp.ActiveInjuries, toInjuryDTO(in))
	}
	if len(measurements) > 0 {
		dto := toMeasurementDTO(measurements[0])
		resp.LatestMeasurement = &dto
		if len(measurements) > 1 {
			resp.Deltas.WeightKg = delta(measurements[0].WeightKg, measurements[1].WeightKg)
			resp.Deltas.WaistCm = delta(measurements[0].WaistCm, measurements[1].WaistCm)
		}
	}
	if len(bio) > 0 {
		dto := toBioimpedanceDTO(bio[0])
		resp.LatestBioimpedance = &dto
		if len(bio) > 1 {
			resp.Deltas.BodyFatPct = delta(bio[0].BodyFatPct, bio[1].BodyFatPct)
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

// delta devolve latest-previous quando os dois lados têm valor; nil quando
// falta qualquer um dos dois — um delta calculado contra "nada medido" não é
// informação, é ruído.
func delta(latest, previous *float64) *float64 {
	if latest == nil || previous == nil {
		return nil
	}
	d := *latest - *previous
	return &d
}
