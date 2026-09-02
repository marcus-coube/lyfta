package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// zeroTime é "sem cursor": a primeira página do histórico.
var zeroTime time.Time

// TestExerciseHistoryAggregatesPerSession é o Aceite do P2.1: três sessões do
// mesmo exercício viram três pontos, com máximo e volume corretos e o mais
// recente primeiro.
func TestExerciseHistoryAggregatesPerSession(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	// Três treinos progredindo: cada série do fixture é 10 reps.
	for _, loads := range [][]float64{{40, 40}, {42.5, 45}, {45, 47.5, 50}} {
		if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
			execEvents(dayA.ID, f.exerciseID, loads...)); err != nil {
			t.Fatalf("executar sessão %v: %v", loads, err)
		}
	}

	points, hasMore, err := f.sessions.ExerciseHistory(ctx, f.tenantID, f.studentID, f.exerciseID, zeroTime, "", 0)
	if err != nil {
		t.Fatalf("histórico: %v", err)
	}
	if hasMore {
		t.Fatalf("três sessões cabem numa página, has_more não deveria vir")
	}
	if len(points) != 3 {
		t.Fatalf("esperava 3 pontos, veio %d", len(points))
	}
	// A ordem é decrescente: a sessão mais recente é a de três séries.
	last := points[0]
	if last.Sets != 3 {
		t.Fatalf("o ponto mais recente deveria ter 3 séries, veio %d", last.Sets)
	}
	if last.MaxLoadKg == nil || *last.MaxLoadKg != 50 {
		t.Fatalf("máximo do último treino deveria ser 50, veio %v", last.MaxLoadKg)
	}
	if want := (45 + 47.5 + 50) * 10; last.TotalVolumeKg != want {
		t.Fatalf("volume do último treino deveria ser %v, veio %v", want, last.TotalVolumeKg)
	}
	if last.TopSet.LoadKg == nil || *last.TopSet.LoadKg != 50 || last.TopSet.SetNo != 3 {
		t.Fatalf("top set deveria ser a série 3 com 50 kg, veio %+v", last.TopSet)
	}
	for i := 1; i < len(points); i++ {
		if !points[i].PerformedAt.Before(points[i-1].PerformedAt) {
			t.Fatalf("os pontos deveriam vir do mais recente para o mais antigo: %+v", points)
		}
	}
}

// TestExerciseHistoryExcludesRevisedSets: o gráfico mostra o que aconteceu,
// não o que foi digitado errado (ADR-003 §5).
func TestExerciseHistoryExcludesRevisedSets(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	// Uma sessão de duas séries: 40 e um 400 digitado com um zero a mais.
	events := execEvents(dayA.ID, f.exerciseID, 40, 400)
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, events); err != nil {
		t.Fatalf("execução: %v", err)
	}
	wrong := events[2]
	revision := domain.SyncEvent{
		ClientID: uuid.NewString(), Type: domain.SyncEventSetRevision,
		PerformedAt: wrong.PerformedAt, SessionClientID: wrong.SessionClientID,
		ExerciseID: f.exerciseID, SetNo: 2, RepsDone: intPtr(10), LoadKg: floatPtr(45),
		Revises: wrong.ClientID,
	}
	if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID, []domain.SyncEvent{revision}); err != nil {
		t.Fatalf("revisão: %v", err)
	}

	points, _, err := f.sessions.ExerciseHistory(ctx, f.tenantID, f.studentID, f.exerciseID, zeroTime, "", 0)
	if err != nil {
		t.Fatalf("histórico: %v", err)
	}
	if len(points) != 1 {
		t.Fatalf("a revisão é da mesma sessão, esperava 1 ponto, veio %d", len(points))
	}
	p := points[0]
	if p.Sets != 2 {
		t.Fatalf("a série corrigida substitui a errada, esperava 2 séries, veio %d", p.Sets)
	}
	if p.MaxLoadKg == nil || *p.MaxLoadKg != 45 {
		t.Fatalf("o 400 kg revisado não pode virar o máximo: %v", p.MaxLoadKg)
	}
	if want := (40 + 45) * 10.0; p.TotalVolumeKg != want {
		t.Fatalf("volume deveria ser %v (sem o log revisado), veio %v", want, p.TotalVolumeKg)
	}
}

// TestExerciseHistoryPaginates: o cursor keyset devolve a página seguinte sem
// repetir nem pular ponto.
func TestExerciseHistoryPaginates(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	for i := 0; i < 3; i++ {
		if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
			execEvents(dayA.ID, f.exerciseID, 40)); err != nil {
			t.Fatalf("executar sessão %d: %v", i, err)
		}
	}

	first, hasMore, err := f.sessions.ExerciseHistory(ctx, f.tenantID, f.studentID, f.exerciseID, zeroTime, "", 2)
	if err != nil {
		t.Fatalf("primeira página: %v", err)
	}
	if len(first) != 2 || !hasMore {
		t.Fatalf("esperava 2 pontos e mais páginas, veio %d/%v", len(first), hasMore)
	}
	cursor := first[len(first)-1]
	second, hasMore, err := f.sessions.ExerciseHistory(ctx, f.tenantID, f.studentID, f.exerciseID,
		cursor.PerformedAt, cursor.SessionID, 2)
	if err != nil {
		t.Fatalf("segunda página: %v", err)
	}
	if len(second) != 1 || hasMore {
		t.Fatalf("a segunda página deveria fechar a lista, veio %d/%v", len(second), hasMore)
	}
	for _, p := range first {
		if p.SessionID == second[0].SessionID {
			t.Fatalf("a segunda página repetiu a sessão %s", p.SessionID)
		}
	}
}

// TestLoggedExercisesListsWhatWasTrained: o índice da tela Evolução só traz
// exercício com execução, e o treinado mais recentemente vem primeiro.
func TestLoggedExercisesListsWhatWasTrained(t *testing.T) {
	f := newExecFixture(t, "A")
	ctx := context.Background()
	dayA := f.dayByLabel(t, "A")

	if items, err := f.sessions.LoggedExercises(ctx, f.tenantID, f.studentID); err != nil {
		t.Fatalf("índice vazio: %v", err)
	} else if len(items) != 0 {
		t.Fatalf("aluno que não treinou não tem histórico, veio %+v", items)
	}

	for i := 0; i < 2; i++ {
		if _, err := f.sessions.ApplyEvents(ctx, f.tenantID, f.studentID,
			execEvents(dayA.ID, f.exerciseID, 40, 42.5)); err != nil {
			t.Fatalf("executar sessão %d: %v", i, err)
		}
	}

	items, err := f.sessions.LoggedExercises(ctx, f.tenantID, f.studentID)
	if err != nil {
		t.Fatalf("índice: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("esperava 1 exercício no índice, veio %d", len(items))
	}
	if items[0].ExerciseID != f.exerciseID || items[0].Sessions != 2 {
		t.Fatalf("esperava o exercício do plano com 2 sessões, veio %+v", items[0])
	}
}
