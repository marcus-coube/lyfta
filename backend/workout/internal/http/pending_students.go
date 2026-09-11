package http

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// PendingStudentsHandler expõe a consulta M2M do job diário de "treino
// pendente" (P3.4) — protegida por RequireInternalToken, não por JWT: quem
// chama é o comms, não um usuário.
type PendingStudentsHandler struct {
	logger  *slog.Logger
	pending *repo.PendingRepo
}

// NewPendingStudentsHandler cria o handler.
func NewPendingStudentsHandler(logger *slog.Logger, pending *repo.PendingRepo) *PendingStudentsHandler {
	return &PendingStudentsHandler{logger: logger, pending: pending}
}

type pendingStudentDTO struct {
	TenantID  string `json:"tenant_id"`
	StudentID string `json:"student_id"`
}

type pendingStudentsResponse struct {
	Items []pendingStudentDTO `json:"items"`
}

// List devolve os alunos com plano ativo e sem sessão registrada em
// [since, until) — o intervalo vem de quem chama (o comms resolve "hoje" no
// timezone configurado por lá, ver Notas de execução da P3.4); o workout só
// responde à pergunta com a janela recebida, sem saber de timezone nenhum.
func (h *PendingStudentsHandler) List(w http.ResponseWriter, r *http.Request) {
	since, until, apiErr := parsePendingRange(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	items, err := h.pending.PendingStudents(r.Context(), since, until)
	if err != nil {
		h.logger.Error("pending_students_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := pendingStudentsResponse{Items: make([]pendingStudentDTO, 0, len(items))}
	for _, it := range items {
		resp.Items = append(resp.Items, pendingStudentDTO{TenantID: it.TenantID, StudentID: it.StudentID})
	}
	writeJSON(w, http.StatusOK, resp)
}

func parsePendingRange(r *http.Request) (since, until time.Time, apiErr *APIError) {
	q := r.URL.Query()
	since, err := time.Parse(time.RFC3339, q.Get("since"))
	if err != nil {
		e := errValidation("since")
		return time.Time{}, time.Time{}, &e
	}
	until, err = time.Parse(time.RFC3339, q.Get("until"))
	if err != nil {
		e := errValidation("until")
		return time.Time{}, time.Time{}, &e
	}
	if !until.After(since) {
		e := errValidation("until")
		return time.Time{}, time.Time{}, &e
	}
	return since, until, nil
}
