package http_test

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
)

// apiToday espelha o payload da tela Hoje do lado do cliente.
type apiToday struct {
	Status string `json:"status"`
	Plan   *struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		VersionID string `json:"version_id"`
		VersionNo int    `json:"version_no"`
	} `json:"plan"`
	Day *struct {
		ID     string `json:"id"`
		Label  string `json:"label"`
		Title  string `json:"title"`
		Blocks []struct {
			BlockType   string `json:"block_type"`
			RestSeconds int    `json:"rest_seconds"`
			Exercises   []struct {
				ExerciseID string `json:"exercise_id"`
				Exercise   *struct {
					Name string `json:"name"`
				} `json:"exercise"`
				Sets []struct {
					SetNo        int      `json:"set_no"`
					RepsMin      *int     `json:"reps_min"`
					TargetLoadKg *float64 `json:"target_load_kg"`
				} `json:"sets"`
			} `json:"exercises"`
		} `json:"blocks"`
	} `json:"day"`
	PreviousLoads []struct {
		ExerciseID string `json:"exercise_id"`
		Sets       []struct {
			SetNo    int      `json:"set_no"`
			RepsDone *int     `json:"reps_done"`
			LoadKg   *float64 `json:"load_kg"`
		} `json:"sets"`
	} `json:"previous_loads"`
	RecentSessions []struct {
		ID            string  `json:"id"`
		DayLabel      string  `json:"day_label"`
		TotalSets     int     `json:"total_sets"`
		TotalVolumeKg float64 `json:"total_volume_kg"`
	} `json:"recent_sessions"`
}

type apiSync struct {
	Results []struct {
		ClientID  string `json:"client_id"`
		Status    string `json:"status"`
		Code      string `json:"code"`
		Field     string `json:"field"`
		SessionID string `json:"session_id"`
	} `json:"results"`
	Accepted   int `json:"accepted"`
	Duplicates int `json:"duplicates"`
	Rejected   int `json:"rejected"`
	State      *struct {
		NextDayID    string `json:"next_day_id"`
		NextDayLabel string `json:"next_day_label"`
	} `json:"state"`
}

type apiPull struct {
	Plan      *apiPlan `json:"plan"`
	Exercises []struct {
		ID string `json:"id"`
	} `json:"exercises"`
	NextCursor string `json:"next_cursor"`
	HasMore    bool   `json:"has_more"`
}

// workoutBatch é a fila que o device acumulou executando um treino. Os
// client_id ficam guardados para o teste poder **reenviar o mesmo lote**, que
// é o Aceite do P1.5.
type workoutBatch struct {
	events        []map[string]any
	sessionClient string
	setClients    []string
}

func newWorkoutBatch(dayID, exerciseID string, loads ...float64) workoutBatch {
	at := time.Now().UTC().Add(-time.Hour)
	b := workoutBatch{sessionClient: uuid.NewString()}
	b.events = append(b.events, map[string]any{
		"client_id":    b.sessionClient,
		"type":         "session_start",
		"performed_at": at.Format(time.RFC3339Nano),
		"payload":      map[string]any{"day_id": dayID},
	})
	for i, load := range loads {
		clientID := uuid.NewString()
		b.setClients = append(b.setClients, clientID)
		b.events = append(b.events, map[string]any{
			"client_id":    clientID,
			"type":         "set_log",
			"performed_at": at.Add(time.Duration(i+1) * time.Minute).Format(time.RFC3339Nano),
			"payload": map[string]any{
				"session_client_id": b.sessionClient,
				"exercise_id":       exerciseID,
				"set_no":            i + 1,
				"reps_done":         10,
				"load_kg":           load,
			},
		})
	}
	b.events = append(b.events, map[string]any{
		"client_id":    uuid.NewString(),
		"type":         "session_finish",
		"performed_at": at.Add(30 * time.Minute).Format(time.RFC3339Nano),
		"payload":      map[string]any{"session_client_id": b.sessionClient},
	})
	return b
}

func (b workoutBatch) body() map[string]any { return map[string]any{"events": b.events} }

func decodeToday(t *testing.T, rec *httptest.ResponseRecorder) apiToday {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/me/today: %d %s", rec.Code, rec.Body.String())
	}
	var today apiToday
	if err := json.Unmarshal(rec.Body.Bytes(), &today); err != nil {
		t.Fatalf("decodificar treino do dia: %v (%s)", err, rec.Body.String())
	}
	return today
}

func decodeSync(t *testing.T, rec *httptest.ResponseRecorder) apiSync {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/sync/workout-logs: %d %s", rec.Code, rec.Body.String())
	}
	var resp apiSync
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decodificar resposta do sync: %v (%s)", err, rec.Body.String())
	}
	return resp
}

// TestTodayAndSyncEndToEnd é o Aceite do P1.5 pela API: o aluno abre o treino
// do dia, executa, sincroniza, a rotação anda A→B — e reenviar o mesmo lote
// não duplica nem avança de novo (ADR-003 §4).
func TestTodayAndSyncEndToEnd(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)

	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	if today.Status != "ready" || today.Day == nil || today.Day.Label != "A" {
		t.Fatalf("o aluno deveria abrir no dia A: %+v", today)
	}
	if today.Plan == nil || today.Plan.VersionNo != 1 {
		t.Fatalf("o payload deveria trazer a versão publicada: %+v", today.Plan)
	}
	// O dia vem pronto para o player: prescrição estruturada e o exercício
	// resolvido, sem uma segunda chamada à biblioteca.
	block := today.Day.Blocks[0]
	if block.BlockType != "superset" || block.RestSeconds != 90 {
		t.Fatalf("bloco veio errado: %+v", block)
	}
	exercise := block.Exercises[0]
	if exercise.Exercise == nil || exercise.Exercise.Name == "" || len(exercise.Sets) != 2 {
		t.Fatalf("exercício do dia veio incompleto: %+v", exercise)
	}
	if *exercise.Sets[0].RepsMin != 8 || *exercise.Sets[0].TargetLoadKg != 40 {
		t.Fatalf("prescrição não chegou ao aluno: %+v", exercise.Sets[0])
	}
	if len(today.PreviousLoads) != 0 || len(today.RecentSessions) != 0 {
		t.Fatalf("primeiro treino não tem histórico: %+v", today)
	}

	dayA := today.Day.ID
	batch := newWorkoutBatch(dayA, a.exerciseID, 40, 42.5)
	sync := decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()))
	if sync.Accepted != 4 || sync.Rejected != 0 || sync.Duplicates != 0 {
		t.Fatalf("lote deveria ser aceito inteiro: %+v", sync)
	}
	if sync.State == nil || sync.State.NextDayLabel != "B" {
		t.Fatalf("a rotação deveria ter avançado para B: %+v", sync.State)
	}

	today = decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	if today.Day == nil || today.Day.Label != "B" {
		t.Fatalf("o próximo treino deveria ser o B: %+v", today.Day)
	}
	if len(today.RecentSessions) != 1 || today.RecentSessions[0].DayLabel != "A" ||
		today.RecentSessions[0].TotalSets != 2 || today.RecentSessions[0].TotalVolumeKg != 825 {
		t.Fatalf("histórico recente veio errado: %+v", today.RecentSessions)
	}

	// Reenvio do lote inteiro: é o que o device faz quando não vê o ACK.
	sync = decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()))
	if sync.Duplicates != 4 || sync.Accepted != 0 {
		t.Fatalf("reenvio deveria ser duplicata em tudo: %+v", sync)
	}
	if sync.State.NextDayLabel != "B" {
		t.Fatalf("reenvio não pode avançar a rotação de novo: %+v", sync.State)
	}

	// Voltando ao dia A, a carga anterior aparece — com duas séries, não
	// quatro: o reenvio não duplicou nada.
	rec := do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student, map[string]any{"day_id": dayA})
	if rec.Code != http.StatusOK {
		t.Fatalf("override para o dia A: %d %s", rec.Code, rec.Body.String())
	}
	today = decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	if today.Day == nil || today.Day.Label != "A" {
		t.Fatalf("override deveria trazer o dia A de volta: %+v", today.Day)
	}
	if len(today.PreviousLoads) != 1 || today.PreviousLoads[0].ExerciseID != a.exerciseID {
		t.Fatalf("carga anterior deveria vir para o exercício do dia: %+v", today.PreviousLoads)
	}
	prev := today.PreviousLoads[0].Sets
	if len(prev) != 2 || *prev[0].LoadKg != 40 || *prev[1].LoadKg != 42.5 || *prev[0].RepsDone != 10 {
		t.Fatalf("carga anterior veio errada: %+v", prev)
	}
}

// TestSyncKeepsDrainingAfterBadEvents: evento ruim volta rejeitado sozinho, o
// resto do lote entra. Um lote que falhasse inteiro travaria a fila do device.
func TestSyncKeepsDrainingAfterBadEvents(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))

	batch := newWorkoutBatch(today.Day.ID, a.exerciseID, 40)
	events := append([]map[string]any{}, batch.events...)
	// Tipo que não existe no contrato.
	events = append(events, map[string]any{
		"client_id": uuid.NewString(), "type": "nap_between_sets",
		"performed_at": time.Now().UTC().Format(time.RFC3339Nano),
		"payload":      map[string]any{},
	})
	// Série apontando para uma sessão que o servidor não conhece.
	events = append(events, map[string]any{
		"client_id": uuid.NewString(), "type": "set_log",
		"performed_at": time.Now().UTC().Format(time.RFC3339Nano),
		"payload": map[string]any{
			"session_client_id": uuid.NewString(), "exercise_id": a.exerciseID,
			"set_no": 1, "reps_done": 10, "load_kg": 40,
		},
	})
	// Sessão num dia que não existe.
	events = append(events, map[string]any{
		"client_id": uuid.NewString(), "type": "session_start",
		"performed_at": time.Now().UTC().Format(time.RFC3339Nano),
		"payload":      map[string]any{"day_id": uuid.NewString()},
	})
	// Relógio do device no futuro (ADR-003: sanidade de performed_at).
	events = append(events, map[string]any{
		"client_id": uuid.NewString(), "type": "session_finish",
		"performed_at": time.Now().UTC().Add(72 * time.Hour).Format(time.RFC3339Nano),
		"payload":      map[string]any{"session_client_id": batch.sessionClient},
	})

	sync := decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student,
		map[string]any{"events": events}))
	if sync.Accepted != 3 || sync.Rejected != 4 {
		t.Fatalf("esperava 3 aceitos e 4 rejeitados: %+v", sync)
	}
	want := []struct{ code, field string }{
		{"invalid_event", "type"},
		{"unknown_session", ""},
		{"unknown_day", ""},
		{"invalid_event", "performed_at"},
	}
	for i, w := range want {
		got := sync.Results[3+i]
		if got.Status != "rejected" || got.Code != w.code || got.Field != w.field {
			t.Fatalf("resultado %d: esperava %s/%s, veio %+v", 3+i, w.code, w.field, got)
		}
	}
	// A sessão boa fechou mesmo assim, e a rotação andou.
	if sync.State == nil || sync.State.NextDayLabel != "B" {
		t.Fatalf("a sessão válida deveria ter avançado a rotação: %+v", sync.State)
	}
}

// TestSyncRejectsBatchWithoutClientID: sem client_id não há o que confirmar —
// o device não conseguiria casar a resposta com a fila dele. É o único caso em
// que o lote inteiro é recusado.
func TestSyncRejectsBatchWithoutClientID(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)

	rec := do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, map[string]any{
		"events": []map[string]any{{
			"type": "session_finish", "performed_at": time.Now().UTC().Format(time.RFC3339Nano),
			"payload": map[string]any{"session_client_id": uuid.NewString()},
		}},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
	}
	var body struct {
		Code   string         `json:"code"`
		Params map[string]any `json:"params"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decodificar erro: %v", err)
	}
	if body.Code != "validation_error" || body.Params["field"] != "events[0].client_id" {
		t.Fatalf("erro deveria apontar o campo: %+v", body)
	}
}

// TestSetRevisionCorrectsLoggedSet: corrigir um registro é evento novo, nunca
// update (ADR-003 §5) — e a leitura passa a mostrar só a correção.
func TestSetRevisionCorrectsLoggedSet(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	dayA := today.Day.ID

	batch := newWorkoutBatch(dayA, a.exerciseID, 40)
	decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, batch.body()))

	sync := decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.student, map[string]any{
		"events": []map[string]any{{
			"client_id": uuid.NewString(), "type": "set_revision",
			"performed_at": time.Now().UTC().Format(time.RFC3339Nano),
			"payload": map[string]any{
				"session_client_id": batch.sessionClient, "exercise_id": a.exerciseID,
				"set_no": 1, "reps_done": 8, "load_kg": 45, "revises": batch.setClients[0],
			},
		}},
	}))
	if sync.Accepted != 1 {
		t.Fatalf("revisão deveria ser aceita: %+v", sync)
	}

	if rec := do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student,
		map[string]any{"day_id": dayA}); rec.Code != http.StatusOK {
		t.Fatalf("override: %d %s", rec.Code, rec.Body.String())
	}
	today = decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	prev := today.PreviousLoads[0].Sets
	if len(prev) != 1 || *prev[0].LoadKg != 45 || *prev[0].RepsDone != 8 {
		t.Fatalf("a carga anterior deveria refletir só a correção: %+v", prev)
	}
}

// TestOverrideDayAccess: o aluno troca o próprio dia, o coach troca o do
// aluno, e dia fora da versão ativa é recusado (ADR-004 §3).
func TestOverrideDayAccess(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	mine := decodePlanBody(t, do(t, a.handler, http.MethodGet, "/v1/me/plan", a.student, nil).Body.Bytes())
	dayB := mine.Version.Days[1].ID

	rec := do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student, map[string]any{"day_id": dayB})
	if rec.Code != http.StatusOK {
		t.Fatalf("aluno trocando o próprio dia: %d %s", rec.Code, rec.Body.String())
	}
	var state struct {
		NextDayID    string `json:"next_day_id"`
		NextDayLabel string `json:"next_day_label"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &state); err != nil {
		t.Fatalf("decodificar estado: %v", err)
	}
	if state.NextDayID != dayB || state.NextDayLabel != "B" {
		t.Fatalf("estado devolvido veio errado: %+v", state)
	}

	// Dia que não é da versão ativa: 422 com o código estável.
	rec = do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student,
		map[string]any{"day_id": uuid.NewString()})
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("esperava 422, veio %d %s", rec.Code, rec.Body.String())
	}
	var body struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Code != "day_not_in_plan" {
		t.Fatalf("esperava day_not_in_plan, veio %q", body.Code)
	}

	// O coach troca o dia do aluno mandando o student_id.
	rec = do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.coach,
		map[string]any{"day_id": mine.Version.Days[0].ID, "student_id": a.studentID})
	if rec.Code != http.StatusOK {
		t.Fatalf("coach trocando o dia do aluno: %d %s", rec.Code, rec.Body.String())
	}

	// Um aluno não mexe no dia de outro.
	rec = do(t, a.handler, http.MethodPost, "/v1/me/plan/override-day", a.student,
		map[string]any{"day_id": dayB, "student_id": uuid.NewString()})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno mexendo no dia de outro deveria dar 403, veio %d %s", rec.Code, rec.Body.String())
	}
}

// TestTodayWithoutPlan: aluno sem plano é um estado da tela, não um erro — o
// cache local guardaria a exceção.
func TestTodayWithoutPlan(t *testing.T) {
	a := builderFixture(t)

	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))
	if today.Status != "no_plan" || today.Day != nil || today.Plan != nil {
		t.Fatalf("aluno sem plano deveria vir como no_plan: %+v", today)
	}
	if today.PreviousLoads == nil || today.RecentSessions == nil {
		t.Fatalf("listas vazias, nunca null: o cliente não deveria tratar nil")
	}
}

// TestSyncIsolatedBetweenTenants: o dia de outro tenant não abre sessão aqui
// (ADR-001) — o RLS filtra e a resposta é rejeição, não 500.
func TestSyncIsolatedBetweenTenants(t *testing.T) {
	a := builderFixture(t)
	createPublishedPlan(t, a)
	today := decodeToday(t, do(t, a.handler, http.MethodGet, "/v1/me/today", a.student, nil))

	sync := decodeSync(t, do(t, a.handler, http.MethodPost, "/v1/sync/workout-logs", a.foreign,
		newWorkoutBatch(today.Day.ID, a.exerciseID, 40).body()))
	if sync.Results[0].Status != "rejected" || sync.Results[0].Code != "unknown_day" {
		t.Fatalf("dia de outro tenant não deveria abrir sessão: %+v", sync.Results[0])
	}
}

// pullCursorAt monta um cursor com a marca d'água escolhida. O cursor é opaco
// para o cliente de verdade; o teste precisa dele determinístico para provar
// que o plano não é reenviado quando nada mudou.
func pullCursorAt(t *testing.T, watermark time.Time) string {
	t.Helper()
	raw, err := json.Marshal(map[string]string{"w": watermark.UTC().Format(time.RFC3339Nano)})
	if err != nil {
		t.Fatalf("montar cursor: %v", err)
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

func decodePull(t *testing.T, rec *httptest.ResponseRecorder) apiPull {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/sync/pull: %d %s", rec.Code, rec.Body.String())
	}
	var pull apiPull
	if err := json.Unmarshal(rec.Body.Bytes(), &pull); err != nil {
		t.Fatalf("decodificar pull: %v (%s)", err, rec.Body.String())
	}
	return pull
}

// TestPullIncremental: sem cursor vem tudo; com cursor à frente do plano, o
// plano não é reenviado; e o cursor pagina a biblioteca.
func TestPullIncremental(t *testing.T) {
	a := builderFixture(t)
	planID := createPublishedPlan(t, a)

	full := decodePull(t, do(t, a.handler, http.MethodGet, "/v1/sync/pull?limit=2", a.student, nil))
	if full.Plan == nil || full.Plan.ID != planID || full.Plan.Version == nil {
		t.Fatalf("sincronização inicial deveria trazer o plano inteiro: %+v", full.Plan)
	}
	if len(full.Exercises) != 2 || !full.HasMore || full.NextCursor == "" {
		t.Fatalf("primeira página da biblioteca veio errada: %d itens, has_more=%v", len(full.Exercises), full.HasMore)
	}

	// Segunda página: itens diferentes dos primeiros.
	page2 := decodePull(t, do(t, a.handler, http.MethodGet, "/v1/sync/pull?limit=2&cursor="+full.NextCursor, a.student, nil))
	for _, novo := range page2.Exercises {
		for _, antigo := range full.Exercises {
			if novo.ID == antigo.ID {
				t.Fatalf("o cursor deveria avançar, exercício %s repetiu", novo.ID)
			}
		}
	}

	// Com a marca d'água à frente de tudo, nada mudou: nem plano, nem
	// biblioteca. É o pull que o app faz a cada abertura com rede.
	quiet := decodePull(t, do(t, a.handler, http.MethodGet,
		"/v1/sync/pull?cursor="+pullCursorAt(t, time.Now().Add(time.Minute)), a.student, nil))
	if quiet.Plan != nil {
		t.Fatalf("plano sem mudança não deveria ser reenviado: %+v", quiet.Plan)
	}

	// Depois de republicar, o plano volta no mesmo cursor.
	if rec := do(t, a.handler, http.MethodPut, "/v1/plans/"+planID+"/draft", a.coach,
		draftBody(a.exerciseID, "A", "B", "C")); rec.Code != http.StatusOK {
		t.Fatalf("editar rascunho: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(t, a.handler, http.MethodPost, "/v1/plans/"+planID+"/publish", a.coach, nil); rec.Code != http.StatusOK {
		t.Fatalf("republicar: %d %s", rec.Code, rec.Body.String())
	}
	changed := decodePull(t, do(t, a.handler, http.MethodGet,
		"/v1/sync/pull?cursor="+pullCursorAt(t, time.Now().Add(-time.Minute)), a.student, nil))
	if changed.Plan == nil || changed.Plan.Version == nil || len(changed.Plan.Version.Days) != 3 {
		t.Fatalf("o plano republicado deveria voltar no pull: %+v", changed.Plan)
	}

	// Cursor corrompido é erro de contrato, não lista vazia.
	rec := do(t, a.handler, http.MethodGet, "/v1/sync/pull?cursor=nao!e!cursor", a.student, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("cursor inválido deveria dar 400, veio %d %s", rec.Code, rec.Body.String())
	}
}
