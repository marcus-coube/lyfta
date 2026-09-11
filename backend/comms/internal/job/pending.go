// Package job roda o job diário de "treino pendente" (P3.4, passo 3): uma
// goroutine de longa duração (mesmo padrão do pubsub.Relay) que, ao passar do
// horário de disparo configurado e ainda não ter varrido hoje, consulta o
// workout (workoutclient.PendingStudents) e manda push pros alunos sem sessão
// no dia — dedupe por notification_log evita reenvio, e pg_advisory_lock
// evita que duas instâncias do comms rodem a varredura ao mesmo tempo.
package job

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/push"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/workoutclient"
)

// pendingLockKey é a chave do pg_advisory_lock — hashtext de um nome fixo,
// não um id de negócio: só precisa ser única o bastante para não colidir com
// outro uso de advisory lock no mesmo banco (não há nenhum outro hoje).
const pendingLockKey = "lyfta_comms_pending_workout_job"

// tickInterval: de quanto em quanto tempo o job confere se já passou do
// horário de disparo e se ainda não varreu hoje. Não precisa ser fino — na
// prática a varredura de verdade acontece uma vez por dia por instância.
const tickInterval = 5 * time.Minute

// pendingStudentsSource é a metade do workoutclient.Client que o job usa —
// uma interface pequena para os testes poderem injetar uma fonte falsa sem
// precisar do serviço workout no ar.
type pendingStudentsSource interface {
	PendingStudents(ctx context.Context, since, until time.Time) ([]workoutclient.PendingStudent, error)
}

// PendingWorkoutJob é o job diário "treino pendente".
type PendingWorkoutJob struct {
	logger      *slog.Logger
	pool        *pgxpool.Pool
	workout     pendingStudentsSource
	logs        *repo.NotificationLogRepo
	notifier    *push.Notifier
	location    *time.Location
	triggerHour int

	lastSweptDay string // "2006-01-02" na location configurada.
}

// NewPendingWorkoutJob cria o job. triggerHour é a hora (0-23) na location
// informada a partir da qual o job passa a considerar "hoje" fechado para
// quem ainda não treinou (plano: "até as 18h locais").
func NewPendingWorkoutJob(
	logger *slog.Logger,
	pool *pgxpool.Pool,
	workout pendingStudentsSource,
	logs *repo.NotificationLogRepo,
	notifier *push.Notifier,
	location *time.Location,
	triggerHour int,
) *PendingWorkoutJob {
	return &PendingWorkoutJob{
		logger: logger, pool: pool, workout: workout, logs: logs,
		notifier: notifier, location: location, triggerHour: triggerHour,
	}
}

// Run inicia o ticker e roda até o contexto ser cancelado — chamado como
// goroutine de longa duração a partir do main.go.
func (j *PendingWorkoutJob) Run(ctx context.Context) {
	// Confere uma vez já na subida: não espera o primeiro tick se o serviço
	// subir depois do horário de disparo.
	j.tick(ctx)

	ticker := time.NewTicker(tickInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			j.tick(ctx)
		}
	}
}

// tick decide se é hora de varrer (já passou do horário, ainda não varreu
// hoje) e, se for, tenta o advisory lock antes de chamar Sweep — não
// bloqueia: se outra instância já segura o lock, esta apenas volta no
// próximo tick.
func (j *PendingWorkoutJob) tick(ctx context.Context) {
	now := time.Now().In(j.location)
	if now.Hour() < j.triggerHour {
		return
	}
	today := now.Format("2006-01-02")
	if today == j.lastSweptDay {
		return
	}

	conn, err := j.pool.Acquire(ctx)
	if err != nil {
		j.logger.Error("pending_job_acquire_conn_failed", slog.Any("error", err))
		return
	}
	defer conn.Release()

	var locked bool
	if err := conn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtext($1)::bigint)", pendingLockKey).Scan(&locked); err != nil {
		j.logger.Error("pending_job_lock_query_failed", slog.Any("error", err))
		return
	}
	if !locked {
		// Outra instância já está varrendo (ou varreu) hoje — não é erro.
		return
	}
	defer func() {
		if _, err := conn.Exec(ctx, "SELECT pg_advisory_unlock(hashtext($1)::bigint)", pendingLockKey); err != nil {
			j.logger.Error("pending_job_unlock_failed", slog.Any("error", err))
		}
	}()

	since := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, j.location)
	until := since.AddDate(0, 0, 1)

	sent, skipped, err := j.Sweep(ctx, since, until)
	if err != nil {
		j.logger.Error("pending_job_sweep_failed", slog.Any("error", err))
		return
	}
	j.lastSweptDay = today
	j.logger.Info("pending_job_swept", slog.Int("sent", sent), slog.Int("skipped_dedupe", skipped))
}

// Sweep é a parte testável do job: dado um intervalo [since, until) já
// resolvido, busca os alunos pendentes no workout e manda push pros que ainda
// não receberam esta notificação nesse intervalo (dedupe por
// notification_log via NotificationLogRepo.ExistsInRange) — exportado para o
// teste exercitar sem depender do relógio real nem do advisory lock.
func (j *PendingWorkoutJob) Sweep(ctx context.Context, since, until time.Time) (sent, skippedDedupe int, err error) {
	students, err := j.workout.PendingStudents(ctx, since, until)
	if err != nil {
		return 0, 0, err
	}

	for _, s := range students {
		already, existsErr := j.logs.ExistsInRange(ctx, s.TenantID, s.StudentID, string(push.KindWorkoutPending), since, until)
		if existsErr != nil {
			j.logger.Error("pending_job_dedupe_check_failed", slog.Any("error", existsErr))
			continue
		}
		if already {
			skippedDedupe++
			continue
		}
		j.notifier.Send(ctx, s.TenantID, s.StudentID, push.KindWorkoutPending, map[string]string{"type": "workout.pending"})
		sent++
	}
	return sent, skippedDedupe, nil
}
