package http

import (
	"context"
	"errors"
	"log/slog"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
	"github.com/marcus-coube/lyfta/workout/internal/security"
)

// planView é a leitura de um plano: a árvore do domínio virando o JSON que o
// app desenha (exercício resolvido no locale, mídia reassinada) e o plano
// completo com histórico de versões.
//
// O builder do coach (P1.4) e o treino do dia do aluno (P1.5) usam a **mesma**
// serialização de propósito: o dia que o aluno executa tem de ser, campo a
// campo, o dia que o coach montou.
type planView struct {
	logger    *slog.Logger
	plans     *repo.PlanRepo
	exercises *repo.ExerciseRepo
	presigner *media.Presigner
	// linker checa o vínculo coach↔aluno nas rotas de professor (ADR-016).
	linker StudentLinker
}

func newPlanView(logger *slog.Logger, plans *repo.PlanRepo, exercises *repo.ExerciseRepo, presigner *media.Presigner, linker StudentLinker) planView {
	return planView{logger: logger, plans: plans, exercises: exercises, presigner: presigner, linker: linker}
}

// checkStudent aplica o vínculo coach↔aluno (ADR-016): nil = pode.
func (v planView) checkStudent(ctx context.Context, claims *security.Claims, studentID string) *APIError {
	return checkStudentLink(ctx, v.logger, v.linker, claims, studentID)
}

// exerciseSummary é o mínimo que o builder e a tela do aluno precisam para
// desenhar o exercício sem uma segunda chamada à biblioteca.
type exerciseSummary struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Locale        string `json:"locale"`
	PrimaryMuscle string `json:"primary_muscle"`
	Equipment     string `json:"equipment"`
	MediaURL      string `json:"media_url,omitempty"`
	MediaType     string `json:"media_type,omitempty"`
	IsGlobal      bool   `json:"is_global"`
}

// daysToDTO serializa a árvore já com o resumo de cada exercício (nome no
// locale e mídia assinada) — uma consulta só para todos os exercícios da
// árvore, não uma por linha.
func (h planView) daysToDTO(ctx context.Context, tenantID string, days []domain.Day, locale domain.Locale) ([]dayDTO, *APIError) {
	ids := map[string]struct{}{}
	for _, d := range days {
		for _, b := range d.Blocks {
			for _, be := range b.Exercises {
				ids[be.ExerciseID] = struct{}{}
			}
		}
	}
	list := make([]string, 0, len(ids))
	for id := range ids {
		list = append(list, id)
	}
	byID, err := h.exercises.ByIDs(ctx, tenantID, list, locale)
	if err != nil {
		h.logger.Error("plan_exercises_failed", slog.Any("error", err))
		apiErr := errInternal()
		return nil, &apiErr
	}

	out := make([]dayDTO, 0, len(days))
	for _, d := range days {
		day := dayDTO{ID: d.ID, Label: d.Label, Position: d.Position, Title: d.Title, Blocks: []blockDTO{}}
		for _, b := range d.Blocks {
			block := blockDTO{
				ID: b.ID, Position: b.Position, BlockType: string(b.BlockType),
				RestSeconds: b.RestSeconds, Exercises: []blockExerciseDTO{},
			}
			for _, be := range b.Exercises {
				item := blockExerciseDTO{
					ID: be.ID, ExerciseID: be.ExerciseID, Position: be.Position,
					Notes: be.Notes, Sets: []setDTO{},
				}
				if ex, ok := byID[be.ExerciseID]; ok {
					item.Exercise = &exerciseSummary{
						ID: ex.ID, Name: ex.DisplayName, Locale: string(ex.NameLocale),
						PrimaryMuscle: ex.PrimaryMuscle, Equipment: ex.Equipment,
						MediaURL:  h.presigner.ResolveURL(ctx, ex.MediaURL),
						MediaType: string(ex.MediaType), IsGlobal: ex.IsGlobal(),
					}
				}
				for _, s := range be.Sets {
					set := setDTO{
						ID: s.ID, SetNo: s.SetNo, RepsMin: s.RepsMin, RepsMax: s.RepsMax,
						TargetLoadKg: s.TargetLoadKg, TargetValue: s.TargetValue,
						RestSeconds: s.RestSeconds, Tempo: s.Tempo,
					}
					if s.TargetUnit != nil {
						set.TargetUnit = string(*s.TargetUnit)
					}
					item.Sets = append(item.Sets, set)
				}
				block.Exercises = append(block.Exercises, item)
			}
			day.Blocks = append(day.Blocks, block)
		}
		out = append(out, day)
	}
	return out, nil
}

// buildResponse monta o plano com o histórico de versões e, se houver versão
// carregada, a árvore inteira com os exercícios resolvidos no locale.
func (h planView) buildResponse(ctx context.Context, tenantID string, plan domain.Plan, version *domain.PlanVersion, locale domain.Locale) (planResponse, *APIError) {
	resp := planResponse{
		ID: plan.ID, StudentID: plan.StudentID, CoachID: plan.CoachID, Title: plan.Title,
		Status: string(plan.Status), CreatedAt: plan.CreatedAt, UpdatedAt: plan.UpdatedAt,
		Versions: []versionRefDTO{},
	}

	versions, err := h.plans.ListVersions(ctx, tenantID, plan.ID)
	if err != nil {
		h.logger.Error("plan_versions_failed", slog.Any("error", err))
		apiErr := errInternal()
		return planResponse{}, &apiErr
	}
	for _, v := range versions {
		resp.Versions = append(resp.Versions, versionRef(v))
	}

	// A rotação do aluno pode estar em outro plano; só reporta o estado quando
	// é este que está ativo.
	state, err := h.plans.GetState(ctx, tenantID, plan.StudentID)
	switch {
	case err == nil && state.PlanID == plan.ID:
		resp.ActiveVersionID = state.ActiveVersionID
		if state.NextDayID != nil {
			resp.NextDayID = *state.NextDayID
		}
	case err != nil && !errors.Is(err, repo.ErrNotFound):
		h.logger.Error("plan_state_failed", slog.Any("error", err))
		apiErr := errInternal()
		return planResponse{}, &apiErr
	}

	if version == nil {
		return resp, nil
	}

	days, err := h.plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		h.logger.Error("plan_tree_failed", slog.Any("error", err))
		apiErr := errInternal()
		return planResponse{}, &apiErr
	}
	dayDTOs, apiErr := h.daysToDTO(ctx, tenantID, days, locale)
	if apiErr != nil {
		return planResponse{}, apiErr
	}
	resp.Version = &versionDTO{versionRefDTO: versionRef(*version), Days: dayDTOs}
	return resp, nil
}
