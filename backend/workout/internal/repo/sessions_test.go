package repo_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// execFixture é um aluno com plano publicado e pronto para executar: o mínimo
// que todo teste de sync precisa montar.
type execFixture struct {
	plans      *repo.PlanRepo
	sessions   *repo.SessionRepo
	tenantID   string
	studentID  string
	planID     string
	days       []domain.Day
	exerciseID string
}

func newExecFixture(t *testing.T, labels ...string) execFixture {
	t.Helper()
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newTenant(), uuid.NewString()
	plans := repo.NewPlanRepo(pool)
	exercise := seedExercise(t, pool, tenantID)
	plan := newPlan(t, plans, tenantID, studentID, uuid.NewString())

	if _, _, err := plans.ReplaceDraft(ctx, tenantID, plan.ID, "", draftDays(exercise.ID, labels...)); err != nil {
		t.Fatalf("gravar rascunho: %v", err)
	}
	version, _, err := plans.PublishDraft(ctx, tenantID, plan.ID, "")
	if err != nil {
		t.Fatalf("publicar: %v", err)
	}
	days, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		t.Fatalf("ler árvore: %v", err)
	}
	return execFixture{
		plans: plans, sessions: repo.NewSessionRepo(pool), tenantID: tenantID,
		studentID: studentID, planID: plan.ID, days: days, exerciseID: exercise.ID,
	}
}

// execEvents monta a fila de uma sessão inteira: começar, registrar as séries
// e terminar — na ordem em que o device empilharia.
func execEvents(dayID, exerciseID string, loads ...float64) []domain.SyncEvent {
	at := time.Now().Add(-time.Hour)
	sessionClientID := uuid.NewString()
	events := []domain.SyncEvent{{
		ClientID: sessionClientID, Type: domain.SyncEventSessionStart,
		PerformedAt: at, DayID: dayID,
	}}
	for i, load := range loads {
		events = append(events, domain.SyncEvent{
			ClientID: uuid.NewString(), Type: domain.SyncEventSetLog,
			PerformedAt: at.Add(time.Duration(i+1) * time.Minute), SessionClientID: sessionClientID,
			ExerciseID: exerciseID, SetNo: i + 1, RepsDone: intPtr(10), LoadKg: floatPtr(load),
		})
	}
	events = append(events, domain.SyncEvent{
		ClientID: uuid.NewString(), Type: domain.SyncEventSessionFinish,
		PerformedAt: at.Add(30 * time.Minute), SessionClientID: sessionClientID,
	})
	return events
}

func (f execFixture) dayByLabel(t *testing.T, label string) domain.Day {
	t.Helper()
	for _, d := range f.days {
		if d.Label == label {
			return d
		}
	}
	t.Fatalf("dia %q não está no plano", label)
	return domain.Day{}
}

func (f execFixture) nextDayLabel(t *testing.T) string {
	t.Helper()
	state, err := f.plans.GetState(context.Background(), f.tenantID, f.studentID)
	if err != nil {
		t.Fatalf("ler estado: %v", err)
	}
	if state.NextDayID == nil {
		return ""
	}
	for _, d := range f.days {
		if d.ID == *state.NextDayID {
			return d.Label
		}
	}
	return "?"
}

// TestRotationIsCircular cobre o ADR-004 §3: concluir a sessão anda um dia, e
// depois do último volta ao primeiro.
func TestRotationIsCircular(t *testing.T) {
	f := newExecFixture(t, "A", "B", "C")
	ctx := context.Background()

	for _, step := range []struct{ run, expected string }{
		{"A", "B"}, {"B", "C"}, {"C", "A"},
	} {
		day := f.dayByLabel(t, step.run)
		if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
			execEvents(day.ID, f.exerciseID, 40)); err != nil {
			t.Fatalf("executar dia %s: %v", step.run, err)
		}
		if got := f.nextDayLabel(t); got != step.expected {
			t.Fatalf("depois de concluir %s a rotação deveria ir para %s, foi para %q", step.run, step.expected, got)
		}
	}
}

// TestFinishWithoutSetsKeepsRotation: abrir o treino e desistir não gasta o
// dia (ADR-004 §3 — "sessão com ≥1 set registrado conta como concluída").
func TestFinishWithoutSetsKeepsRotation(t *testing.T) {
	f := newExecFixture(t, "A", "B")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	// Sem nenhuma série entre o início e o fim.
	events := execEvents(dayA.ID, f.exerciseID)
	results, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, events)
	if err != nil {
		t.Fatalf("aplicar lote: %v", err)
	}
	if len(results) != 2 || results[0].Status != domain.SyncStatusAccepted || results[1].Status != domain.SyncStatusAccepted {
		t.Fatalf("início e fim deveriam ser aceitos: %+v", results)
	}
	if got := f.nextDayLabel(t); got != "A" {
		t.Fatalf("rotação não deveria andar sem série registrada, foi para %q", got)
	}
}

// TestSyncBatchIsIdempotent é o Aceite do P1.5: reenviar o mesmo lote não
// duplica log nem avança a rotação duas vezes (ADR-003 §4).
func TestSyncBatchIsIdempotent(t *testing.T) {
	f := newExecFixture(t, "A", "B", "C")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")
	events := execEvents(dayA.ID, f.exerciseID, 40, 42.5)

	first, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, events)
	if err != nil {
		t.Fatalf("primeiro envio: %v", err)
	}
	for _, res := range first {
		if res.Status != domain.SyncStatusAccepted {
			t.Fatalf("primeiro envio deveria aceitar tudo: %+v", first)
		}
	}
	if got := f.nextDayLabel(t); got != "B" {
		t.Fatalf("rotação deveria estar em B, está em %q", got)
	}

	second, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, events)
	if err != nil {
		t.Fatalf("reenvio: %v", err)
	}
	for _, res := range second {
		if res.Status != domain.SyncStatusDuplicate {
			t.Fatalf("reenvio deveria ser duplicata em todos: %+v", second)
		}
	}
	if got := f.nextDayLabel(t); got != "B" {
		t.Fatalf("reenvio não pode avançar a rotação de novo: está em %q", got)
	}

	// E o histórico continua com as duas séries, não quatro.
	loads, err := f.sessions.PreviousLoads(ctx, f.tenantID, f.studentID, []string{f.exerciseID})
	if err != nil {
		t.Fatalf("carga anterior: %v", err)
	}
	if got := len(loads[f.exerciseID].Sets); got != 2 {
		t.Fatalf("esperava 2 séries no histórico, veio %d", got)
	}
}

// TestRejectedEventDoesNotAbortBatch: um evento ruim volta rejeitado e o
// resto do lote continua sendo gravado — sem isso a fila do device travaria.
func TestRejectedEventDoesNotAbortBatch(t *testing.T) {
	f := newExecFixture(t, "A", "B")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	events := execEvents(dayA.ID, f.exerciseID, 40)
	sessionClientID := events[0].ClientID
	// Entre a série boa e o fim, um log apontando para uma sessão que não
	// existe (evento de outro device, fila corrompida).
	orphan := domain.SyncEvent{
		ClientID: uuid.NewString(), Type: domain.SyncEventSetLog,
		PerformedAt: time.Now().Add(-time.Minute), SessionClientID: uuid.NewString(),
		ExerciseID: f.exerciseID, SetNo: 1, RepsDone: intPtr(10), LoadKg: floatPtr(50),
	}
	// E um log com exercício que este tenant não enxerga.
	foreign := domain.SyncEvent{
		ClientID: uuid.NewString(), Type: domain.SyncEventSetLog,
		PerformedAt: time.Now().Add(-time.Minute), SessionClientID: sessionClientID,
		ExerciseID: uuid.NewString(), SetNo: 2, RepsDone: intPtr(10), LoadKg: floatPtr(50),
	}
	batch := append([]domain.SyncEvent{events[0], events[1], orphan, foreign}, events[2])

	results, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, batch)
	if err != nil {
		t.Fatalf("aplicar lote: %v", err)
	}
	want := []struct {
		status domain.SyncStatus
		code   string
	}{
		{domain.SyncStatusAccepted, ""},
		{domain.SyncStatusAccepted, ""},
		{domain.SyncStatusRejected, repo.RejectUnknownSession},
		{domain.SyncStatusRejected, repo.RejectUnknownExercise},
		{domain.SyncStatusAccepted, ""},
	}
	if len(results) != len(want) {
		t.Fatalf("esperava %d resultados, veio %d: %+v", len(want), len(results), results)
	}
	for i, w := range want {
		if results[i].Status != w.status || results[i].Code != w.code {
			t.Fatalf("evento %d: esperava %s/%q, veio %s/%q", i, w.status, w.code, results[i].Status, results[i].Code)
		}
	}
	// A sessão fechou e a rotação andou, apesar dos dois eventos rejeitados.
	if got := f.nextDayLabel(t); got != "B" {
		t.Fatalf("rotação deveria ter avançado para B, está em %q", got)
	}
}

// TestSessionRequiresPublishedDay: rascunho não é treino — só dia de versão
// publicada abre sessão (ADR-004 §1).
func TestSessionRequiresPublishedDay(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()

	// Uma v2 em rascunho, ainda não publicada.
	_, draftDaysSaved, err := f.plans.ReplaceDraft(ctx, f.tenantID, f.planID, "", draftDays(f.exerciseID, "A", "B"))
	if err != nil {
		t.Fatalf("abrir rascunho v2: %v", err)
	}

	results, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
		execEvents(draftDaysSaved[1].ID, f.exerciseID, 40))
	if err != nil {
		t.Fatalf("aplicar lote: %v", err)
	}
	if results[0].Status != domain.SyncStatusRejected || results[0].Code != repo.RejectUnknownDay {
		t.Fatalf("dia de rascunho não deveria abrir sessão: %+v", results[0])
	}
}

// TestPreviousLoadCrossesPlans é o outro Aceite do P1.5: a carga anterior é
// o último log por `exercise_id`, mesmo que o aluno tenha trocado de plano
// (ADR-004 — exercise_id é o eixo estável).
func TestPreviousLoadCrossesPlans(t *testing.T) {
	f := newExecFixture(t, "A", "B")
	ctx := context.Background()

	// Primeiro plano: 40 kg no dia A.
	dayA := f.dayByLabel(t, "A")
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
		execEvents(dayA.ID, f.exerciseID, 40)); err != nil {
		t.Fatalf("executar plano 1: %v", err)
	}

	// O coach troca o aluno para outro plano, com o mesmo exercício.
	novo := newPlan(t, f.plans, f.tenantID, f.studentID, uuid.NewString())
	if _, _, err := f.plans.ReplaceDraft(ctx, f.tenantID, novo.ID, "", draftDays(f.exerciseID, "X")); err != nil {
		t.Fatalf("rascunho do plano 2: %v", err)
	}
	v2, _, err := f.plans.PublishDraft(ctx, f.tenantID, novo.ID, "")
	if err != nil {
		t.Fatalf("publicar plano 2: %v", err)
	}
	novosDias, err := f.plans.GetVersionTree(ctx, f.tenantID, v2.ID)
	if err != nil {
		t.Fatalf("ler árvore do plano 2: %v", err)
	}
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
		execEvents(novosDias[0].ID, f.exerciseID, 47.5)); err != nil {
		t.Fatalf("executar plano 2: %v", err)
	}

	loads, err := f.sessions.PreviousLoads(ctx, f.tenantID, f.studentID, []string{f.exerciseID})
	if err != nil {
		t.Fatalf("carga anterior: %v", err)
	}
	prev, ok := loads[f.exerciseID]
	if !ok || len(prev.Sets) != 1 {
		t.Fatalf("esperava a última sessão com 1 série, veio %+v", prev)
	}
	if got := *prev.Sets[0].LoadKg; got != 47.5 {
		t.Fatalf("carga anterior deveria ser a do plano novo (47.5), veio %v", got)
	}
}

// TestSetRevisionHidesOriginal: corrigir um registro não edita o fato — o log
// antigo continua na tabela e some das leituras (ADR-003 §5).
func TestSetRevisionHidesOriginal(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	events := execEvents(dayA.ID, f.exerciseID, 40)
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, events); err != nil {
		t.Fatalf("execução original: %v", err)
	}

	original := events[1]
	revision := domain.SyncEvent{
		ClientID: uuid.NewString(), Type: domain.SyncEventSetRevision,
		PerformedAt: original.PerformedAt, SessionClientID: original.SessionClientID,
		ExerciseID: f.exerciseID, SetNo: 1, RepsDone: intPtr(8), LoadKg: floatPtr(45),
		Revises: original.ClientID,
	}
	results, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, []domain.SyncEvent{revision})
	if err != nil {
		t.Fatalf("revisão: %v", err)
	}
	if results[0].Status != domain.SyncStatusAccepted {
		t.Fatalf("revisão deveria ser aceita: %+v", results[0])
	}

	loads, err := f.sessions.PreviousLoads(ctx, f.tenantID, f.studentID, []string{f.exerciseID})
	if err != nil {
		t.Fatalf("carga anterior: %v", err)
	}
	prev := loads[f.exerciseID]
	if len(prev.Sets) != 1 || *prev.Sets[0].LoadKg != 45 || *prev.Sets[0].RepsDone != 8 {
		t.Fatalf("a leitura deveria mostrar só a versão corrigida, veio %+v", prev.Sets)
	}

	// Revisar um log que o servidor não tem é rejeitado: revisão órfã não
	// esconde nada e ficaria invisível para sempre.
	orphan := revision
	orphan.ClientID, orphan.Revises = uuid.NewString(), uuid.NewString()
	results, err = f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, []domain.SyncEvent{orphan})
	if err != nil {
		t.Fatalf("revisão órfã: %v", err)
	}
	if results[0].Status != domain.SyncStatusRejected || results[0].Code != repo.RejectUnknownRevisedLog {
		t.Fatalf("revisão órfã deveria ser rejeitada: %+v", results[0])
	}
}

// TestExecutionIsolatedBetweenStudentsAndTenants: o histórico é do aluno, e o
// tenant não vaza (ADR-001).
func TestExecutionIsolatedBetweenStudentsAndTenants(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
		execEvents(dayA.ID, f.exerciseID, 40)); err != nil {
		t.Fatalf("executar: %v", err)
	}

	// Outro aluno do mesmo tenant não herda a carga anterior.
	other := uuid.NewString()
	loads, err := f.sessions.PreviousLoads(ctx, f.tenantID, other, []string{f.exerciseID})
	if err != nil {
		t.Fatalf("carga anterior do outro aluno: %v", err)
	}
	if len(loads) != 0 {
		t.Fatalf("carga anterior é por aluno, veio %+v", loads)
	}
	recent, err := f.sessions.RecentSessions(ctx, f.tenantID, other, 0)
	if err != nil {
		t.Fatalf("histórico do outro aluno: %v", err)
	}
	if len(recent) != 0 {
		t.Fatalf("histórico é por aluno, veio %+v", recent)
	}

	// E outro tenant não vê nada, nem com o id certo do aluno.
	loads, err = f.sessions.PreviousLoads(ctx, newTenant(), f.studentID, []string{f.exerciseID})
	if err != nil {
		t.Fatalf("carga anterior cross-tenant: %v", err)
	}
	if len(loads) != 0 {
		t.Fatalf("RLS deveria esconder a execução de outro tenant, veio %+v", loads)
	}

	// O resumo do aluno certo continua completo.
	recent, err = f.sessions.RecentSessions(ctx, f.tenantID, f.studentID, 0)
	if err != nil {
		t.Fatalf("histórico: %v", err)
	}
	if len(recent) != 1 || recent[0].DayLabel != "A" || recent[0].TotalSets != 1 {
		t.Fatalf("resumo da sessão veio errado: %+v", recent)
	}
	if recent[0].TotalVolumeKg != 400 {
		t.Fatalf("volume deveria ser 10 reps × 40 kg = 400, veio %v", recent[0].TotalVolumeKg)
	}
	if recent[0].FinishedAt == nil {
		t.Fatalf("sessão concluída deveria ter finished_at")
	}
}

// TestOverrideNextDay cobre o override manual da rotação (ADR-004 §3) e a
// recusa de um dia que não é da versão ativa.
func TestOverrideNextDay(t *testing.T) {
	f := newExecFixture(t, "A", "B", "C")
	ctx := context.Background()
	dayC := f.dayByLabel(t, "C")

	state, err := f.plans.SetNextDay(ctx, f.tenantID, f.studentID, dayC.ID)
	if err != nil {
		t.Fatalf("override: %v", err)
	}
	if state.NextDayID == nil || *state.NextDayID != dayC.ID {
		t.Fatalf("override deveria apontar para C, veio %v", state.NextDayID)
	}

	// Dia de outro plano (ou inexistente) não entra na rotação deste aluno.
	if _, err := f.plans.SetNextDay(ctx, f.tenantID, f.studentID, uuid.NewString()); err == nil {
		t.Fatal("dia fora da versão ativa deveria ser recusado")
	} else if !errors.Is(err, repo.ErrDayNotInPlan) {
		t.Fatalf("esperava ErrDayNotInPlan, veio %v", err)
	}

	// Depois de concluir C, a rotação volta ao A a partir do override.
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
		execEvents(dayC.ID, f.exerciseID, 40)); err != nil {
		t.Fatalf("executar C: %v", err)
	}
	if got := f.nextDayLabel(t); got != "A" {
		t.Fatalf("depois do C a rotação volta ao A, veio %q", got)
	}
}
