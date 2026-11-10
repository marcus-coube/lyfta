package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// maxOverviewStudents é o teto de ids por chamada: o tamanho de página da
// lista de alunos (P5.2/P5.4).
const maxOverviewStudents = 100

// OverviewHandler serve o resumo em lote (último treino + plano ativo) que a
// lista de alunos pede uma vez por página e que o dashboard (P8) reaproveita.
type OverviewHandler struct {
	logger   *slog.Logger
	overview *repo.OverviewRepo
	linker   StudentLinker
}

// NewOverviewHandler cria o handler.
func NewOverviewHandler(logger *slog.Logger, overview *repo.OverviewRepo, linker StudentLinker) *OverviewHandler {
	return &OverviewHandler{logger: logger, overview: overview, linker: linker}
}

type overviewRequest struct {
	StudentIDs []string `json:"student_ids"`
}

type overviewPlanDTO struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	// VersionNo é a versão publicada em uso (a que a rotação aponta).
	VersionNo int `json:"version_no"`
}

type overviewItemDTO struct {
	StudentID     string           `json:"student_id"`
	LastSessionAt *time.Time       `json:"last_session_at"`
	ActivePlan    *overviewPlanDTO `json:"active_plan"`
}

// Students responde POST /v1/students/overview. Ids que o ator não pode ver
// (coach só enxerga os vinculados a ele; ADR-016) ou que não têm dados
// simplesmente não voltam — não há 404 por item. O app calcula "sem treinar
// há N dias" a partir de `last_session_at` (nulo = nunca treinou).
func (h *OverviewHandler) Students(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	var req overviewRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	if len(req.StudentIDs) == 0 || len(req.StudentIDs) > maxOverviewStudents {
		writeError(w, errValidation("student_ids"))
		return
	}
	for _, id := range req.StudentIDs {
		if _, err := uuid.Parse(id); err != nil {
			writeError(w, errValidation("student_ids"))
			return
		}
	}

	visible, err := h.linker.VisibleStudents(r.Context(), claims.TenantID, claims.Subject, claims.Roles, req.StudentIDs)
	if err != nil {
		h.logger.Error("coach_link_check_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	rows, err := h.overview.Overviews(r.Context(), claims.TenantID, visible)
	if err != nil {
		h.logger.Error("students_overview_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	items := make([]overviewItemDTO, 0, len(rows))
	for _, o := range rows {
		it := overviewItemDTO{StudentID: o.StudentID}
		if o.LastSessionAt != nil {
			utc := o.LastSessionAt.UTC()
			it.LastSessionAt = &utc
		}
		if o.ActivePlanID != nil && o.ActivePlan != nil && o.ActiveVersion != nil {
			it.ActivePlan = &overviewPlanDTO{ID: *o.ActivePlanID, Title: *o.ActivePlan, VersionNo: *o.ActiveVersion}
		}
		items = append(items, it)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}
