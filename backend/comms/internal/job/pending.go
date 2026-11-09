// Package job roda o job diário de "treino pendente" (P3.4, passo 3): uma
// goroutine de longa duração (mesmo padrão do pubsub.Relay) que, ao passar do
// horário de disparo configurado e ainda não ter varrido hoje, consulta o
// workout (workoutclient.PendingStudents) e manda push pros alunos sem sessão
// no dia — dedupe por notification_log evita reenvio, e pg_advisory_lock
// evita que duas instâncias do comms rodem a varredura ao mesmo tempo.
//
// O "dia" e a hora de disparo são do fuso de cada tenant (P5.1, ADR-007 §3):
// a lista de tenants vem do identity por M2M (cache de 10 min) e a varredura
// roda uma vez por fuso distinto, com a janela [since, until) daquele fuso.
package job

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/coachlink"
	"github.com/marcus-coube/lyfta/comms/internal/push"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/tenantclient"
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
	PendingStudents(ctx context.Context, since, until time.Time, tenantIDs []string) ([]workoutclient.PendingStudent, error)
}

// studentStatusSource consulta no identity, em lote, o status dos alunos
// (coachlink.Client): aluno inativo não recebe o push (P5.2).
type studentStatusSource interface {
	StudentStatuses(ctx context.Context, refs []coachlink.StudentRef) (map[coachlink.StudentRef]string, error)
}

// statusActive é o status do aluno que treina (identity).
const statusActive = "active"

// tenantSource lista os tenants com o fuso de cada um (tenantclient.Client).
type tenantSource interface {
	List(ctx context.Context) ([]tenantclient.Tenant, error)
}

// PendingWorkoutJob é o job diário "treino pendente".
type PendingWorkoutJob struct {
	logger      *slog.Logger
	pool        *pgxpool.Pool
	workout     pendingStudentsSource
	tenants     tenantSource
	students    studentStatusSource
	logs        *repo.NotificationLogRepo
	notifier    *push.Notifier
	triggerHour int
	now         func() time.Time

	// lastSwept guarda, por fuso, o último dia ("2006-01-02" naquele fuso) já
	// varrido nesta instância.
	lastSwept map[string]string
}

// NewPendingWorkoutJob cria o job. triggerHour é a hora (0-23), no fuso de
// cada tenant, a partir da qual o job passa a considerar "hoje" fechado para
// quem ainda não treinou (plano: "até as 18h locais").
func NewPendingWorkoutJob(
	logger *slog.Logger,
	pool *pgxpool.Pool,
	workout pendingStudentsSource,
	tenants tenantSource,
	students studentStatusSource,
	logs *repo.NotificationLogRepo,
	notifier *push.Notifier,
	triggerHour int,
) *PendingWorkoutJob {
	return &PendingWorkoutJob{
		logger: logger, pool: pool, workout: workout, tenants: tenants, students: students, logs: logs,
		notifier: notifier, triggerHour: triggerHour, now: time.Now,
		lastSwept: map[string]string{},
	}
}

// WithClock troca o relógio do job — só para teste (relógio fake).
func (j *PendingWorkoutJob) WithClock(now func() time.Time) *PendingWorkoutJob {
	j.now = now
	return j
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

// dueWindow é um fuso cuja hora de disparo já passou hoje e que ainda não foi
// varrido: a janela [since, until) do dia civil local e os tenants dele.
type dueWindow struct {
	timezone     string
	day          string
	since, until time.Time
	tenantIDs    []string
}

// Tick decide, por fuso, se é hora de varrer (já passou do horário local e
// ainda não varreu o dia local) e, se algum estiver no ponto, tenta o
// advisory lock antes de chamar Sweep — não bloqueia: se outra instância já
// segura o lock, esta apenas volta no próximo tick. Exportado para o teste
// com relógio fake.
func (j *PendingWorkoutJob) Tick(ctx context.Context) { j.tick(ctx) }

func (j *PendingWorkoutJob) tick(ctx context.Context) {
	tenants, err := j.tenants.List(ctx)
	if err != nil {
		j.logger.Error("pending_job_list_tenants_failed", slog.Any("error", err))
		return
	}

	byZone := map[string][]string{}
	for _, t := range tenants {
		byZone[t.Timezone] = append(byZone[t.Timezone], t.ID)
	}

	var due []dueWindow
	utcNow := j.now()
	for tz, ids := range byZone {
		loc, err := time.LoadLocation(tz)
		if err != nil {
			j.logger.Error("pending_job_invalid_timezone", slog.String("timezone", tz), slog.Any("error", err))
			continue
		}
		now := utcNow.In(loc)
		if now.Hour() < j.triggerHour {
			continue
		}
		day := now.Format("2006-01-02")
		if j.lastSwept[tz] == day {
			continue
		}
		since := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
		due = append(due, dueWindow{timezone: tz, day: day, since: since, until: since.AddDate(0, 0, 1), tenantIDs: ids})
	}
	if len(due) == 0 {
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

	for _, w := range due {
		sent, skipped, err := j.Sweep(ctx, w.since, w.until, w.tenantIDs)
		if err != nil {
			j.logger.Error("pending_job_sweep_failed", slog.String("timezone", w.timezone), slog.Any("error", err))
			continue
		}
		j.lastSwept[w.timezone] = w.day
		j.logger.Info("pending_job_swept", slog.String("timezone", w.timezone), slog.Int("sent", sent), slog.Int("skipped_dedupe", skipped))
	}
}

// Sweep é a parte testável do job: dado um intervalo [since, until) já
// resolvido, busca os alunos pendentes no workout e manda push pros que ainda
// não receberam esta notificação nesse intervalo (dedupe por
// notification_log via NotificationLogRepo.ExistsInRange) — exportado para o
// teste exercitar sem depender do relógio real nem do advisory lock.
//
// tenantIDs são os tenants daquele fuso — o workout só devolve alunos deles;
// lista vazia não varre ninguém.
func (j *PendingWorkoutJob) Sweep(ctx context.Context, since, until time.Time, tenantIDs []string) (sent, skippedDedupe int, err error) {
	if len(tenantIDs) == 0 {
		return 0, 0, nil
	}
	pending, err := j.workout.PendingStudents(ctx, since, until, tenantIDs)
	if err != nil {
		return 0, 0, err
	}

	// Aluno inativo (ou que o identity não conhece mais) fica fora. Uma
	// chamada em lote por varredura; falha do identity aborta a varredura: o
	// próximo tick refaz, e o dedupe protege quem já recebeu.
	refs := make([]coachlink.StudentRef, len(pending))
	for i, s := range pending {
		refs[i] = coachlink.StudentRef{TenantID: s.TenantID, StudentID: s.StudentID}
	}
	statuses, err := j.students.StudentStatuses(ctx, refs)
	if err != nil {
		return 0, 0, err
	}

	for i, s := range pending {
		if statuses[refs[i]] != statusActive {
			continue
		}
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
