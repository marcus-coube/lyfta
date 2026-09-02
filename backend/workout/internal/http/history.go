package http

import (
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// HistoryHandler é a leitura do progresso por exercício (P2.1): a série
// temporal que vira o gráfico de carga e o índice de exercícios já treinados.
//
// Cada rota tem duas portas — `/me/...` para o aluno, `/students/{id}/...`
// para o professor —, e as duas caem no mesmo repositório. O que muda é só de
// onde sai o `student_id`: da claim ou da URL. Ler o histórico de um aluno é
// de qualquer professor do tenant, o mesmo critério que o P1.4 usou para ler
// plano; o vínculo coach↔aluno vive no identity (dívida anotada lá).
type HistoryHandler struct {
	logger    *slog.Logger
	sessions  *repo.SessionRepo
	exercises *repo.ExerciseRepo
	presigner *media.Presigner
}

// NewHistoryHandler cria o handler de histórico.
func NewHistoryHandler(logger *slog.Logger, sessions *repo.SessionRepo, exercises *repo.ExerciseRepo, presigner *media.Presigner) *HistoryHandler {
	return &HistoryHandler{logger: logger, sessions: sessions, exercises: exercises, presigner: presigner}
}

type historyTopSetDTO struct {
	SetNo    int      `json:"set_no"`
	RepsDone *int     `json:"reps_done"`
	LoadKg   *float64 `json:"load_kg"`
}

// historyPointDTO é um ponto do gráfico. `max_load_kg` é nulo — e não zero —
// quando o exercício não tem carga: a tela precisa distinguir "sem carga" de
// "carga zero" para escolher o eixo.
type historyPointDTO struct {
	SessionID     string           `json:"session_id"`
	PerformedAt   time.Time        `json:"performed_at"`
	Sets          int              `json:"sets"`
	MaxLoadKg     *float64         `json:"max_load_kg"`
	TotalVolumeKg float64          `json:"total_volume_kg"`
	TopSet        historyTopSetDTO `json:"top_set"`
}

type historyResponse struct {
	ExerciseID string            `json:"exercise_id"`
	Items      []historyPointDTO `json:"items"`
	NextCursor string            `json:"next_cursor,omitempty"`
}

type loggedExerciseDTO struct {
	Sessions        int              `json:"sessions"`
	LastPerformedAt time.Time        `json:"last_performed_at"`
	Exercise        *exerciseSummary `json:"exercise,omitempty"`
}

type loggedExercisesResponse struct {
	Items []loggedExerciseDTO `json:"items"`
}

// MyHistory devolve ao aluno a progressão dele num exercício. O aluno é o
// `sub` da claim: não há parâmetro de aluno, então nenhum token lê o
// histórico de outra pessoa.
func (h *HistoryHandler) MyHistory(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.history(w, r, claims.TenantID, claims.Subject)
}

// StudentHistory é a mesma leitura vista pelo professor, com o aluno na URL.
func (h *HistoryHandler) StudentHistory(w http.ResponseWriter, r *http.Request) {
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
	h.history(w, r, tenantID, studentID)
}

// MyLogged é o índice da tela Evolução do aluno.
func (h *HistoryHandler) MyLogged(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}
	h.logged(w, r, claims.TenantID, claims.Subject)
}

// StudentLogged é o índice do aluno visto pelo professor.
func (h *HistoryHandler) StudentLogged(w http.ResponseWriter, r *http.Request) {
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
	h.logged(w, r, tenantID, studentID)
}

func (h *HistoryHandler) history(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	exerciseID := chi.URLParam(r, "exercise_id")
	if _, err := uuid.Parse(exerciseID); err != nil {
		writeError(w, errValidation("exercise_id"))
		return
	}

	q := r.URL.Query()
	limit := 0
	if raw := q.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			writeError(w, errValidation("limit"))
			return
		}
		limit = parsed
	}

	var (
		cursorAt time.Time
		cursorID string
	)
	if raw := strings.TrimSpace(q.Get("cursor")); raw != "" {
		at, id, err := decodeHistoryCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		cursorAt, cursorID = at, id
	}

	points, hasMore, err := h.sessions.ExerciseHistory(r.Context(), tenantID, studentID,
		exerciseID, cursorAt, cursorID, limit)
	if err != nil {
		h.logger.Error("history_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	// Exercício que este tenant não enxerga não devolve página vazia: sem o
	// 404 a tela do app não teria como distinguir "id errado" de "ainda não
	// treinou isso".
	if len(points) == 0 {
		if _, err := h.exercises.GetByID(r.Context(), tenantID, exerciseID); err != nil {
			writeError(w, errNotFound("exercise"))
			return
		}
	}

	resp := historyResponse{ExerciseID: exerciseID, Items: make([]historyPointDTO, 0, len(points))}
	for _, p := range points {
		resp.Items = append(resp.Items, historyPointDTO{
			SessionID: p.SessionID, PerformedAt: p.PerformedAt, Sets: p.Sets,
			MaxLoadKg: p.MaxLoadKg, TotalVolumeKg: p.TotalVolumeKg,
			TopSet: historyTopSetDTO{
				SetNo: p.TopSet.SetNo, RepsDone: p.TopSet.RepsDone, LoadKg: p.TopSet.LoadKg,
			},
		})
	}
	if hasMore && len(points) > 0 {
		last := points[len(points)-1]
		resp.NextCursor = encodeHistoryCursor(last.PerformedAt, last.SessionID)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *HistoryHandler) logged(w http.ResponseWriter, r *http.Request, tenantID, studentID string) {
	items, err := h.sessions.LoggedExercises(r.Context(), tenantID, studentID)
	if err != nil {
		h.logger.Error("logged_exercises_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	ids := make([]string, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.ExerciseID)
	}
	byID, err := h.exercises.ByIDs(r.Context(), tenantID, ids, requestLocaleOrDefault(r))
	if err != nil {
		h.logger.Error("logged_exercises_names_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := loggedExercisesResponse{Items: make([]loggedExerciseDTO, 0, len(items))}
	for _, item := range items {
		// Exercício apagado da biblioteca depois de treinado sai do índice: o
		// seletor da tela Evolução não tem o que desenhar sem nome nem mídia.
		ex, ok := byID[item.ExerciseID]
		if !ok {
			continue
		}
		resp.Items = append(resp.Items, loggedExerciseDTO{
			Sessions: item.Sessions, LastPerformedAt: item.LastPerformedAt,
			Exercise: &exerciseSummary{
				ID: ex.ID, Name: ex.DisplayName, Locale: string(ex.NameLocale),
				PrimaryMuscle: ex.PrimaryMuscle, Equipment: ex.Equipment,
				MediaURL:  h.presigner.ResolveURL(r.Context(), ex.MediaURL),
				MediaType: string(ex.MediaType), IsGlobal: ex.IsGlobal(),
			},
		})
	}
	writeJSON(w, http.StatusOK, resp)
}

// encodeHistoryCursor/decodeHistoryCursor empacotam o keyset do histórico
// (instante + sessão) no mesmo formato opaco da biblioteca.
func encodeHistoryCursor(at time.Time, sessionID string) string {
	return encodeCursor(at.UTC().Format(time.RFC3339Nano), sessionID)
}

func decodeHistoryCursor(raw string) (time.Time, string, error) {
	sortKey, id, err := decodeCursor(raw)
	if err != nil {
		return time.Time{}, "", err
	}
	at, err := time.Parse(time.RFC3339Nano, sortKey)
	if err != nil {
		return time.Time{}, "", err
	}
	if _, err := uuid.Parse(id); err != nil {
		return time.Time{}, "", err
	}
	return at, id, nil
}
