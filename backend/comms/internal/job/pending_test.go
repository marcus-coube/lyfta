package job_test

import (
	"context"
	"log/slog"
	"os"
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

func (f *fakeWorkoutSource) PendingStudents(ctx context.Context, since, until time.Time) ([]workoutclient.PendingStudent, error) {
	return f.students, nil
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
	j := job.NewPendingWorkoutJob(logger, pool, source, notifications, notifier, time.UTC, 18)

	since := time.Now().UTC().Truncate(24 * time.Hour)
	until := since.AddDate(0, 0, 1)

	sent1, skipped1, err := j.Sweep(ctx, since, until)
	if err != nil {
		t.Fatalf("primeira varredura: %v", err)
	}
	if sent1 != 1 || skipped1 != 0 {
		t.Fatalf("primeira varredura deveria mandar 1 e pular 0, veio sent=%d skipped=%d", sent1, skipped1)
	}
	if pusher.count() != 1 {
		t.Fatalf("esperava 1 push enviado de verdade, veio %d", pusher.count())
	}

	sent2, skipped2, err := j.Sweep(ctx, since, until)
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
	j := job.NewPendingWorkoutJob(logger, pool, source, notifications, notifier, time.UTC, 18)

	// Intervalo de "hoje" começando amanhã de propósito, só para garantir que
	// o log de "ontem" (gravado agora, com sent_at = now()) fica ANTES do
	// `since` deste teste e não seja contado no dedupe.
	since := time.Now().UTC().Add(time.Hour)
	until := since.AddDate(0, 0, 1)

	sent, skipped, err := j.Sweep(ctx, since, until)
	if err != nil {
		t.Fatalf("varredura: %v", err)
	}
	if sent != 1 || skipped != 0 {
		t.Fatalf("log fora da janela não deveria disparar dedupe, veio sent=%d skipped=%d", sent, skipped)
	}
}
