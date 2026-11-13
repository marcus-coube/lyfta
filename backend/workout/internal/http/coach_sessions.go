package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// Sessão do aluno vista pelo professor (P11.1). Mora no HistoryHandler: lê as
// mesmas tabelas, pela mesma porta `/students/{id}` — o middleware
// RequireStudentLink já barrou quem não é owner nem professor do aluno.

const maxLookupClientIDs = 50

type lookupSessionsRequest struct {
	ClientIDs []string `json:"client_ids"`
}

// coachSessionDTO é o resumo da sessão; as métricas saem da mesma função do
// resumo do aluno (domain.MeasureSession).
type coachSessionDTO struct {
	ClientID        string     `json:"client_id"`
	DayLabel        string     `json:"day_label"`
	PlanTitle       string     `json:"plan_title"`
	StartedAt       time.Time  `json:"started_at"`
	FinishedAt      *time.Time `json:"finished_at"`
	DurationSeconds *int       `json:"duration_seconds"`
	SetsCount       int        `json:"sets_count"`
	RepsTotal       int        `json:"reps_total"`
	VolumeKg        float64    `json:"volume_kg"`
}

func coachSessionFromSummary(s domain.SessionSummary) coachSessionDTO {
	return coachSessionDTO{
		ClientID: s.ClientID, DayLabel: s.DayLabel, PlanTitle: s.PlanTitle,
		StartedAt: s.StartedAt, FinishedAt: s.FinishedAt, DurationSeconds: s.DurationSeconds,
		SetsCount: s.TotalSets, RepsTotal: s.RepsTotal, VolumeKg: s.TotalVolumeKg,
	}
}

type lookupSessionsResponse struct {
	Items []coachSessionDTO `json:"items"`
}

// LookupStudentSessions responde POST /v1/students/{id}/sessions/lookup.
func (h *HistoryHandler) LookupStudentSessions(w http.ResponseWriter, r *http.Request) {
	tenantID, studentID, ok := h.studentFromURL(w, r)
	if !ok {
		return
	}
	var req lookupSessionsRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}
	seen := make(map[string]bool, len(req.ClientIDs))
	ids := make([]string, 0, len(req.ClientIDs))
	for _, id := range req.ClientIDs {
		if _, err := uuid.Parse(id); err != nil {
			writeError(w, errValidation("client_ids"))
			return
		}
		if !seen[id] {
			seen[id] = true
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 || len(ids) > maxLookupClientIDs {
		writeError(w, errValidation("client_ids"))
		return
	}

	items, err := h.sessions.SessionsByClientIDs(r.Context(), tenantID, studentID, ids)
	if err != nil {
		h.logger.Error("sessions_lookup_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	resp := lookupSessionsResponse{Items: make([]coachSessionDTO, 0, len(items))}
	for _, s := range items {
		resp.Items = append(resp.Items, coachSessionFromSummary(s))
	}
	writeJSON(w, http.StatusOK, resp)
}

type coachPrescribedDTO struct {
	RepsMin      *int     `json:"reps_min"`
	RepsMax      *int     `json:"reps_max"`
	TargetLoadKg *float64 `json:"target_load_kg"`
	TargetUnit   *string  `json:"target_unit"`
	TargetValue  *float64 `json:"target_value"`
}

type coachDoneDTO struct {
	RepsDone    *int      `json:"reps_done"`
	LoadKg      *float64  `json:"load_kg"`
	RPE         *float64  `json:"rpe"`
	PerformedAt time.Time `json:"performed_at"`
	Revised     bool      `json:"revised"`
}

type coachSetDTO struct {
	SetNo         int                `json:"set_no"`
	Label         *string            `json:"label"`
	VariationName *string            `json:"variation_name"`
	Prescribed    coachPrescribedDTO `json:"prescribed"`
	Done          *coachDoneDTO      `json:"done"`
}

type coachExerciseDTO struct {
	ExerciseID string        `json:"exercise_id"`
	Name       string        `json:"name"`
	Sets       []coachSetDTO `json:"sets"`
}

type coachBlockDTO struct {
	BlockType string             `json:"block_type"`
	Exercises []coachExerciseDTO `json:"exercises"`
}

type coachSessionDetailDTO struct {
	coachSessionDTO
	Blocks []coachBlockDTO `json:"blocks"`
}

// snapshotView é só o que o detalhe lê do snapshot congelado (ADR-004 §2).
type snapshotView struct {
	Blocks []struct {
		BlockType string `json:"block_type"`
		Exercises []struct {
			ExerciseID string `json:"exercise_id"`
			Name       string `json:"name"`
			Sets       []struct {
				SetNo        int      `json:"set_no"`
				RepsMin      *int     `json:"reps_min"`
				RepsMax      *int     `json:"reps_max"`
				TargetLoadKg *float64 `json:"target_load_kg"`
				TargetUnit   *string  `json:"target_unit"`
				TargetValue  *float64 `json:"target_value"`
				Label        *string  `json:"label"`
				Variation    *struct {
					Name string `json:"name"`
				} `json:"variation"`
			} `json:"sets"`
		} `json:"exercises"`
	} `json:"blocks"`
}

// StudentSession responde GET /v1/students/{id}/sessions/{client_id}.
func (h *HistoryHandler) StudentSession(w http.ResponseWriter, r *http.Request) {
	tenantID, studentID, ok := h.studentFromURL(w, r)
	if !ok {
		return
	}
	clientID := chi.URLParam(r, "client_id")
	if _, err := uuid.Parse(clientID); err != nil {
		writeError(w, errSessionNotFound())
		return
	}

	detail, err := h.sessions.SessionDetailByClientID(r.Context(), tenantID, studentID, clientID)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errSessionNotFound())
		return
	}
	if err != nil {
		h.logger.Error("student_session_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}
	var snap snapshotView
	if err := json.Unmarshal(detail.Snapshot, &snap); err != nil {
		h.logger.Error("student_session_snapshot_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	// Feito por (exercício, série): a lista já vem só com logs efetivos; se
	// houver mais de um para a mesma série, o mais recente vence.
	type setKey struct {
		exerciseID string
		setNo      int
	}
	done := make(map[setKey]domain.SetLog, len(detail.Logs))
	for _, l := range detail.Logs {
		k := setKey{l.ExerciseID, l.SetNo}
		if prev, ok := done[k]; !ok || !l.PerformedAt.Before(prev.PerformedAt) {
			done[k] = l
		}
	}

	ids := make([]string, 0, 8)
	for _, b := range snap.Blocks {
		for _, e := range b.Exercises {
			ids = append(ids, e.ExerciseID)
		}
	}
	names, err := h.exercises.ByIDs(r.Context(), tenantID, ids, requestLocaleOrDefault(r))
	if err != nil {
		h.logger.Error("student_session_names_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := coachSessionDetailDTO{
		coachSessionDTO: coachSessionFromSummary(detail.Summary),
		Blocks:          make([]coachBlockDTO, 0, len(snap.Blocks)),
	}
	// O app numera o set_no de forma contínua por exercício dentro da sessão
	// (`TodayData.runs`/`setNoOffset`): um exercício que reaparece em outro
	// bloco do dia loga a partir de offset+1. O casamento com o log segue a
	// mesma numeração; o `set_no` exibido continua o do snapshot.
	used := make(map[string]int, len(ids))
	for _, b := range snap.Blocks {
		block := coachBlockDTO{BlockType: b.BlockType, Exercises: make([]coachExerciseDTO, 0, len(b.Exercises))}
		for _, e := range b.Exercises {
			name := e.Name
			if ex, ok := names[e.ExerciseID]; ok && ex.DisplayName != "" {
				name = ex.DisplayName
			}
			exercise := coachExerciseDTO{ExerciseID: e.ExerciseID, Name: name, Sets: make([]coachSetDTO, 0, len(e.Sets))}
			offset := used[e.ExerciseID]
			used[e.ExerciseID] = offset + len(e.Sets)
			for i, s := range e.Sets {
				set := coachSetDTO{
					SetNo: s.SetNo, Label: s.Label,
					Prescribed: coachPrescribedDTO{
						RepsMin: s.RepsMin, RepsMax: s.RepsMax, TargetLoadKg: s.TargetLoadKg,
						TargetUnit: s.TargetUnit, TargetValue: s.TargetValue,
					},
				}
				if s.Variation != nil {
					set.VariationName = &s.Variation.Name
				}
				if l, ok := done[setKey{e.ExerciseID, offset + i + 1}]; ok {
					set.Done = &coachDoneDTO{
						RepsDone: l.RepsDone, LoadKg: l.LoadKg, RPE: l.RPE,
						PerformedAt: l.PerformedAt, Revised: l.Revises != nil,
					}
				}
				exercise.Sets = append(exercise.Sets, set)
			}
			block.Exercises = append(block.Exercises, exercise)
		}
		resp.Blocks = append(resp.Blocks, block)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *HistoryHandler) studentFromURL(w http.ResponseWriter, r *http.Request) (tenantID, studentID string, ok bool) {
	tenantID, ok = TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return "", "", false
	}
	studentID = chi.URLParam(r, "id")
	if _, err := uuid.Parse(studentID); err != nil {
		writeError(w, errValidation("id"))
		return "", "", false
	}
	return tenantID, studentID, true
}
