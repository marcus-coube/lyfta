package http

import (
	"context"
	"log/slog"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// StaleAfter é o "sem treinar há 7+ dias" do dashboard (P8.1).
const StaleAfter = 7 * 24 * time.Hour

// TodayRoster é o que o painel precisa do identity: quem é aluno ativo de
// quem (ADR-016). coachlink.Client implementa.
type TodayRoster interface {
	StudentsOf(ctx context.Context, tenantID, coachID string) (map[string]struct{}, error)
	ExistingStudents(ctx context.Context, tenantID string, studentIDs []string) (map[string]string, error)
	ActiveStudentsOfTenant(ctx context.Context, tenantID string) ([]string, error)
}

// CoachTodayHandler serve GET /v1/coach/today.
type CoachTodayHandler struct {
	logger *slog.Logger
	today  *repo.TodayRepo
	roster TodayRoster
	now    func() time.Time
}

// NewCoachTodayHandler cria o handler.
func NewCoachTodayHandler(logger *slog.Logger, today *repo.TodayRepo, roster TodayRoster) *CoachTodayHandler {
	return &CoachTodayHandler{logger: logger, today: today, roster: roster, now: time.Now}
}

type coachTodayItemDTO struct {
	StudentID     string     `json:"student_id"`
	State         string     `json:"state"`
	LastSessionAt *time.Time `json:"last_session_at"`
	// Stale: nunca treinou ou o último treino tem 7+ dias.
	Stale bool `json:"stale"`
}

type coachTodayResponse struct {
	// Date é o dia (AAAA-MM-DD) no fuso da claim `tz`.
	Date   string              `json:"date"`
	Counts map[string]int      `json:"counts"`
	Items  []coachTodayItemDTO `json:"items"`
}

// Estados de hoje de um aluno ativo, em ordem de precedência.
const (
	coachTrained    = "trained"
	coachInProgress = "in_progress"
	coachPending    = "pending"
	coachNoPlan     = "no_plan"
)

// Get devolve os alunos ativos do vínculo com o estado de hoje no fuso do
// tenant (claim `tz`; ausente ou inválido = UTC): trained (sessão finalizada
// hoje), in_progress (sessão de hoje sem finalizar), pending (plano ativo e
// nada hoje) e no_plan. Coach vê os alunos dele; owner vê todos, com
// `?coach_id=` opcional (ignorado para coach puro). Alunos inativos ou ainda
// convidados ficam fora.
func (h *CoachTodayHandler) Get(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	isOwner := false
	for _, role := range claims.Roles {
		if role == "owner" {
			isOwner = true
		}
	}
	coachID := claims.Subject
	if isOwner {
		coachID = ""
		if raw := strings.TrimSpace(r.URL.Query().Get("coach_id")); raw != "" {
			if _, err := uuid.Parse(raw); err != nil {
				writeError(w, errValidation("coach_id"))
				return
			}
			coachID = raw
		}
	}

	var ids []string
	var err error
	if coachID == "" {
		ids, err = h.roster.ActiveStudentsOfTenant(r.Context(), claims.TenantID)
	} else {
		var linked map[string]struct{}
		linked, err = h.roster.StudentsOf(r.Context(), claims.TenantID, coachID)
		if err == nil {
			ids = make([]string, 0, len(linked))
			for id := range linked {
				ids = append(ids, id)
			}
			sort.Strings(ids)
			var statuses map[string]string
			if statuses, err = h.roster.ExistingStudents(r.Context(), claims.TenantID, ids); err == nil {
				active := ids[:0]
				for _, id := range ids {
					if statuses[id] == "active" {
						active = append(active, id)
					}
				}
				ids = active
			}
		}
	}
	if err != nil {
		h.logger.Error("coach_today_roster_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	loc := time.UTC
	if claims.Timezone != "" {
		if l, lerr := time.LoadLocation(claims.Timezone); lerr == nil {
			loc = l
		}
	}
	now := h.now()
	local := now.In(loc)
	since := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	until := since.AddDate(0, 0, 1)

	rows, err := h.today.Today(r.Context(), claims.TenantID, ids, since, until)
	if err != nil {
		h.logger.Error("coach_today_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := coachTodayResponse{
		Date:   since.Format("2006-01-02"),
		Counts: map[string]int{coachTrained: 0, coachInProgress: 0, coachPending: 0, coachNoPlan: 0, "stale": 0},
		Items:  make([]coachTodayItemDTO, 0, len(rows)),
	}
	staleBefore := now.Add(-StaleAfter)
	for _, row := range rows {
		state := coachNoPlan
		switch {
		case row.FinishedToday:
			state = coachTrained
		case row.SessionsToday > 0:
			state = coachInProgress
		case row.HasPlan:
			state = coachPending
		}
		item := coachTodayItemDTO{StudentID: row.StudentID, State: state}
		if row.LastSessionAt != nil {
			utc := row.LastSessionAt.UTC()
			item.LastSessionAt = &utc
		}
		item.Stale = row.LastSessionAt == nil || row.LastSessionAt.Before(staleBefore)
		resp.Counts[state]++
		if item.Stale {
			resp.Counts["stale"]++
		}
		resp.Items = append(resp.Items, item)
	}
	writeJSON(w, http.StatusOK, resp)
}
