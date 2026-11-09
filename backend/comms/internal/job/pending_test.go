package job_test

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/fcm"
	"github.com/marcus-coube/lyfta/comms/internal/job"
	"github.com/marcus-coube/lyfta/comms/internal/push"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/tenantclient"
	"github.com/marcus-coube/lyfta/comms/internal/workoutclient"
)

// testPool abre um pool contra o Postgres de dev (lyfta_comms) — mesmo
// padrão dos demais testes de integração do serviço.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_comms?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		skipOrFail(t, "banco indisponível para teste de integração: "+err.Error())
		return nil
	}
	t.Cleanup(pool.Close)
	return pool
}

func skipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// fakeWorkoutSource devolve sempre a mesma lista fixa — o job não precisa do
// serviço workout no ar para o teste do Sweep, só de algo que satisfaça a
// mesma pergunta (ADR-013 §2: comms nunca importa código do workout, então
// nem faria sentido usar o tipo real aqui).
type fakeWorkoutSource struct {
	students []workoutclient.PendingStudent
}

func (f *fakeWorkoutSource) PendingStudents(ctx context.Context, since, until time.Time, tenantIDs []string) ([]workoutclient.PendingStudent, error) {
	return onlyTenants(f.students, tenantIDs), nil
}

// onlyTenants imita o filtro do workout: só devolve alunos dos tenants pedidos.
func onlyTenants(students []workoutclient.PendingStudent, tenantIDs []string) []workoutclient.PendingStudent {
	var out []workoutclient.PendingStudent
	for _, s := range students {
		if slices.Contains(tenantIDs, s.TenantID) {
			out = append(out, s)
		}
	}
	return out
}

// fakePusher registra as mensagens enviadas em memória — o teste do dedupe
// não precisa (nem deve) bater na Google.
type fakePusher struct {
	mu   sync.Mutex
	sent []fcm.Message
}

func (f *fakePusher) Send(ctx context.Context, msg fcm.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, msg)
	return nil
}

func (f *fakePusher) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.sent)
}

// fakeStudents responde o status por aluno; quem não está no mapa é `active`.
type fakeStudents struct {
	status map[string]string
	err    error
}

func (f *fakeStudents) StudentStatus(ctx context.Context, tenantID, studentID string) (string, bool, error) {
	if f.err != nil {
		return "", false, f.err
	}
	if s, ok := f.status[studentID]; ok {
		return s, s != "", nil
	}
	return "active", true, nil
}

// TestSweepDoesNotDuplicateSameDay cobre o Aceite da P3.4: "job não duplica
// no mesmo dia". Duas chamadas a Sweep com o mesmo intervalo e a mesma lista
// de alunos pendentes só mandam push uma vez — a segunda encontra o
// notification_log já gravado pela primeira (ExistsInRange) e pula.
func TestSweepDoesNotDuplicateSameDay(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)

	tenantID, studentID := uuid.NewString(), uuid.NewString()
	deviceTokens := repo.NewDeviceTokenRepo(pool)
	if _, err := deviceTokens.Upsert(ctx, tenantID, studentID, domain.PlatformAndroid, "tok-"+uuid.NewString(), domain.LocalePTBR); err != nil {
		t.Fatalf("registrar device token: %v", err)
	}

	notifications := repo.NewNotificationLogRepo(pool)
	pusher := &fakePusher{}
	notifier := push.NewNotifier(logger, deviceTokens, notifications, pusher)

	source := &fakeWorkoutSource{students: []workoutclient.PendingStudent{{TenantID: tenantID, StudentID: studentID}}}
	students := &fakeStudents{}
	j := job.NewPendingWorkoutJob(logger, pool, source, nil, students, notifications, notifier, 18)

	since := time.Now().UTC().Truncate(24 * time.Hour)
	until := since.AddDate(0, 0, 1)

	sent1, skipped1, err := j.Sweep(ctx, since, until, []string{tenantID})
	if err != nil {
		t.Fatalf("primeira varredura: %v", err)
	}
	if sent1 != 1 || skipped1 != 0 {
		t.Fatalf("primeira varredura deveria mandar 1 e pular 0, veio sent=%d skipped=%d", sent1, skipped1)
	}
	if pusher.count() != 1 {
		t.Fatalf("esperava 1 push enviado de verdade, veio %d", pusher.count())
	}

	sent2, skipped2, err := j.Sweep(ctx, since, until, []string{tenantID})
	if err != nil {
		t.Fatalf("segunda varredura: %v", err)
	}
	if sent2 != 0 || skipped2 != 1 {
		t.Fatalf("segunda varredura deveria pular por dedupe, veio sent=%d skipped=%d", sent2, skipped2)
	}
	if pusher.count() != 1 {
		t.Fatalf("segunda varredura não deveria mandar push de novo, total ficou %d", pusher.count())
	}
}

// TestSweepSkipsInactiveStudents cobre o Aceite da P5.2: aluno inativo sai do
// push de pendente, e falha do identity aborta a varredura.
func TestSweepSkipsInactiveStudents(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)

	tenantID, active, inactive := uuid.NewString(), uuid.NewString(), uuid.NewString()
	deviceTokens := repo.NewDeviceTokenRepo(pool)
	for _, id := range []string{active, inactive} {
		if _, err := deviceTokens.Upsert(ctx, tenantID, id, domain.PlatformAndroid, "tok-"+uuid.NewString(), domain.LocalePTBR); err != nil {
			t.Fatalf("registrar device token: %v", err)
		}
	}
	notifications := repo.NewNotificationLogRepo(pool)
	pusher := &fakePusher{}
	notifier := push.NewNotifier(logger, deviceTokens, notifications, pusher)
	source := &fakeWorkoutSource{students: []workoutclient.PendingStudent{
		{TenantID: tenantID, StudentID: active}, {TenantID: tenantID, StudentID: inactive},
	}}
	students := &fakeStudents{status: map[string]string{inactive: "inactive"}}
	j := job.NewPendingWorkoutJob(logger, pool, source, nil, students, notifications, notifier, 18)

	since := time.Now().UTC().Truncate(24 * time.Hour)
	sent, _, err := j.Sweep(ctx, since, since.AddDate(0, 0, 1), []string{tenantID})
	if err != nil || sent != 1 || pusher.count() != 1 {
		t.Fatalf("só o aluno ativo deveria receber: sent=%d push=%d err=%v", sent, pusher.count(), err)
	}

	students.err = errors.New("identity fora")
	if _, _, err := j.Sweep(ctx, since, since.AddDate(0, 0, 1), []string{tenantID}); err == nil {
		t.Fatalf("falha do identity deveria abortar a varredura")
	}
}

// TestSweepDedupeIsPerDayWindow cobre a borda do dedupe: um envio de ONTEM
// (fora do intervalo [since, until) de hoje) não impede o envio de hoje —
// senão o aluno nunca mais receberia o lembrete depois do primeiro dia.
func TestSweepDedupeIsPerDayWindow(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)

	tenantID, studentID := uuid.NewString(), uuid.NewString()
	deviceTokens := repo.NewDeviceTokenRepo(pool)
	if _, err := deviceTokens.Upsert(ctx, tenantID, studentID, domain.PlatformAndroid, "tok-"+uuid.NewString(), domain.LocalePTBR); err != nil {
		t.Fatalf("registrar device token: %v", err)
	}

	notifications := repo.NewNotificationLogRepo(pool)
	pusher := &fakePusher{}
	notifier := push.NewNotifier(logger, deviceTokens, notifications, pusher)

	// Simula o envio de ontem gravando o log diretamente.
	if err := notifications.Record(ctx, tenantID, studentID, string(push.KindWorkoutPending), map[string]any{"title": "ontem"}); err != nil {
		t.Fatalf("gravar log de ontem: %v", err)
	}

	source := &fakeWorkoutSource{students: []workoutclient.PendingStudent{{TenantID: tenantID, StudentID: studentID}}}
	students := &fakeStudents{}
	j := job.NewPendingWorkoutJob(logger, pool, source, nil, students, notifications, notifier, 18)

	// Intervalo de "hoje" começando amanhã de propósito, só para garantir que
	// o log de "ontem" (gravado agora, com sent_at = now()) fica ANTES do
	// `since` deste teste e não seja contado no dedupe.
	since := time.Now().UTC().Add(time.Hour)
	until := since.AddDate(0, 0, 1)

	sent, skipped, err := j.Sweep(ctx, since, until, []string{tenantID})
	if err != nil {
		t.Fatalf("varredura: %v", err)
	}
	if sent != 1 || skipped != 0 {
		t.Fatalf("log fora da janela não deveria disparar dedupe, veio sent=%d skipped=%d", sent, skipped)
	}
}

// fakeTenants devolve uma lista fixa de tenants com fuso.
type fakeTenants struct{ items []tenantclient.Tenant }

func (f *fakeTenants) List(ctx context.Context) ([]tenantclient.Tenant, error) {
	return f.items, nil
}

// windowRecorder devolve os alunos dos tenants pedidos e registra as janelas
// e os tenants de cada chamada.
type windowRecorder struct {
	students []workoutclient.PendingStudent
	mu       sync.Mutex
	since    []time.Time
	tenants  [][]string
}

func (w *windowRecorder) PendingStudents(ctx context.Context, since, until time.Time, tenantIDs []string) ([]workoutclient.PendingStudent, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.since = append(w.since, since)
	w.tenants = append(w.tenants, tenantIDs)
	return onlyTenants(w.students, tenantIDs), nil
}

// TestTickRunsInEachTenantTimezone cobre o Aceite da P5.1: dois tenants com
// fusos diferentes recebem o push de pendente no horário local de cada um.
// Relógio fake: 09:00 UTC = 06:00 em São Paulo (antes das 18h) e 18:00 em
// Tóquio (no ponto); 21:00 UTC = 18:00 em São Paulo.
func TestTickRunsInEachTenantTimezone(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)

	spTenant, tokyoTenant := uuid.NewString(), uuid.NewString()
	spStudent, tokyoStudent := uuid.NewString(), uuid.NewString()
	deviceTokens := repo.NewDeviceTokenRepo(pool)
	for _, p := range [][2]string{{spTenant, spStudent}, {tokyoTenant, tokyoStudent}} {
		if _, err := deviceTokens.Upsert(ctx, p[0], p[1], domain.PlatformAndroid, "tok-"+uuid.NewString(), domain.LocalePTBR); err != nil {
			t.Fatalf("registrar device token: %v", err)
		}
	}

	notifications := repo.NewNotificationLogRepo(pool)
	pusher := &fakePusher{}
	notifier := push.NewNotifier(logger, deviceTokens, notifications, pusher)
	source := &windowRecorder{students: []workoutclient.PendingStudent{
		{TenantID: spTenant, StudentID: spStudent},
		{TenantID: tokyoTenant, StudentID: tokyoStudent},
	}}
	tenants := &fakeTenants{items: []tenantclient.Tenant{
		{ID: spTenant, Timezone: "America/Sao_Paulo"},
		{ID: tokyoTenant, Timezone: "Asia/Tokyo"},
	}}

	clock := time.Date(2030, 3, 10, 9, 0, 0, 0, time.UTC)
	students := &fakeStudents{}
	j := job.NewPendingWorkoutJob(logger, pool, source, tenants, students, notifications, notifier, 18).
		WithClock(func() time.Time { return clock })

	notified := func(tenantID, studentID string) bool {
		ok, err := notifications.ExistsInRange(ctx, tenantID, studentID, string(push.KindWorkoutPending), time.Now().Add(-time.Hour), time.Now().Add(time.Hour))
		if err != nil {
			t.Fatalf("consultar log: %v", err)
		}
		return ok
	}

	// 09:00 UTC: só Tóquio está no ponto (18:00 local).
	j.Tick(ctx)
	if pusher.count() != 1 {
		t.Fatalf("às 09:00 UTC só Tóquio deveria receber, enviados=%d", pusher.count())
	}
	if !notified(tokyoTenant, tokyoStudent) || notified(spTenant, spStudent) {
		t.Fatalf("às 09:00 UTC só o aluno de Tóquio deveria ter sido notificado")
	}
	tokyoSince := time.Date(2030, 3, 10, 0, 0, 0, 0, time.FixedZone("JST", 9*3600))
	if len(source.since) != 1 || !source.since[0].Equal(tokyoSince) {
		t.Fatalf("janela de Tóquio = %v, esperava %v", source.since, tokyoSince)
	}
	if !slices.Equal(source.tenants[0], []string{tokyoTenant}) {
		t.Fatalf("varredura de Tóquio deveria pedir só o tenant de Tóquio, pediu %v", source.tenants[0])
	}

	// Mesmo instante de novo: nada a fazer (Tóquio já varrido, SP antes das 18h).
	j.Tick(ctx)
	if pusher.count() != 1 || len(source.since) != 1 {
		t.Fatalf("segundo tick não deveria varrer de novo: enviados=%d varreduras=%d", pusher.count(), len(source.since))
	}

	// 21:00 UTC: São Paulo chega às 18:00 locais.
	clock = time.Date(2030, 3, 10, 21, 0, 0, 0, time.UTC)
	j.Tick(ctx)
	if pusher.count() != 2 {
		t.Fatalf("às 21:00 UTC São Paulo deveria receber, enviados=%d", pusher.count())
	}
	if !notified(spTenant, spStudent) {
		t.Fatalf("o aluno de São Paulo deveria ter sido notificado às 21:00 UTC")
	}
	spSince := time.Date(2030, 3, 10, 0, 0, 0, 0, time.FixedZone("BRT", -3*3600))
	if len(source.since) != 2 || !source.since[1].Equal(spSince) {
		t.Fatalf("janela de São Paulo = %v, esperava %v", source.since, spSince)
	}
	if !slices.Equal(source.tenants[1], []string{spTenant}) {
		t.Fatalf("varredura de São Paulo deveria pedir só o tenant de SP, pediu %v", source.tenants[1])
	}
}
