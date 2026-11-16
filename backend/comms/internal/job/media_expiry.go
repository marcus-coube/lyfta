package job

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// mediaExpiryInterval é o intervalo do tick da expiração da mídia de execução
// (ADR-020 §3, P12.1): o prazo é de dias, então minutos de atraso não importam.
const mediaExpiryInterval = tickInterval

// mediaExpiryBatch é quantas mídias vencidas por tenant cada passada apaga.
const mediaExpiryBatch = 100

// objectDeleter é a metade do media.Presigner que o job usa.
type objectDeleter interface {
	DeleteObject(ctx context.Context, key string) error
}

// MediaExpiryJob apaga a mídia de execução vencida: o objeto no storage e,
// só depois, `deleted_at` (a linha fica, sem a chave, para o histórico "mídia
// expirada"). Falha no storage não marca nada — o próximo tick tenta de novo.
//
// O tick usa o mesmo pg_advisory_lock dos demais jobs do comms
// (pendingLockKey): com duas instâncias, só uma apaga por vez; quem não pega
// o lock volta no próximo tick. O relógio é injetável (WithClock) — os testes
// adiantam o tempo em vez de esperar 7 ou 30 dias.
type MediaExpiryJob struct {
	logger  *slog.Logger
	pool    *pgxpool.Pool
	media   *repo.SessionMediaRepo
	store   objectDeleter
	tenants tenantSource
	now     func() time.Time
}

// NewMediaExpiryJob cria o job. tenants lista os tenants (identity, M2M): o
// RLS exige um tenant por consulta, como na varredura do treino pendente.
func NewMediaExpiryJob(logger *slog.Logger, pool *pgxpool.Pool, media *repo.SessionMediaRepo, store objectDeleter, tenants tenantSource) *MediaExpiryJob {
	return &MediaExpiryJob{logger: logger, pool: pool, media: media, store: store, tenants: tenants, now: time.Now}
}

// WithClock troca o relógio do job — só para teste.
func (j *MediaExpiryJob) WithClock(now func() time.Time) *MediaExpiryJob {
	j.now = now
	return j
}

// Run confere já na subida e depois a cada tick, até o contexto cancelar.
func (j *MediaExpiryJob) Run(ctx context.Context) {
	j.Tick(ctx)
	ticker := time.NewTicker(mediaExpiryInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			j.Tick(ctx)
		}
	}
}

// Tick pega o advisory lock (sem bloquear) e roda uma varredura.
func (j *MediaExpiryJob) Tick(ctx context.Context) {
	conn, err := j.pool.Acquire(ctx)
	if err != nil {
		j.logger.Error("media_expiry_acquire_conn_failed", slog.Any("error", err))
		return
	}
	defer conn.Release()

	var locked bool
	if err := conn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtext($1)::bigint)", pendingLockKey).Scan(&locked); err != nil {
		j.logger.Error("media_expiry_lock_query_failed", slog.Any("error", err))
		return
	}
	if !locked {
		return // outra instância (ou o job de pendentes) segura o lock
	}
	defer func() {
		if _, err := conn.Exec(ctx, "SELECT pg_advisory_unlock(hashtext($1)::bigint)", pendingLockKey); err != nil {
			j.logger.Error("media_expiry_unlock_failed", slog.Any("error", err))
		}
	}()

	deleted, failed, err := j.Sweep(ctx)
	if err != nil {
		j.logger.Error("media_expiry_sweep_failed", slog.Any("error", err))
		return
	}
	if deleted > 0 || failed > 0 {
		j.logger.Info("media_expiry_swept", slog.Int("deleted", deleted), slog.Int("failed", failed))
	}
}

// Sweep apaga a mídia com delete_after <= agora, tenant a tenant. Exportado
// para o teste exercitar sem o advisory lock.
func (j *MediaExpiryJob) Sweep(ctx context.Context) (deleted, failed int, err error) {
	tenants, err := j.tenants.List(ctx)
	if err != nil {
		return 0, 0, err
	}
	now := j.now()
	for _, t := range tenants {
		for {
			due, listErr := j.media.ListDue(ctx, t.ID, now, mediaExpiryBatch)
			if listErr != nil {
				j.logger.Error("media_expiry_list_failed", slog.String("tenant_id", t.ID), slog.Any("error", listErr))
				break
			}
			ok := 0
			for _, m := range due {
				if delErr := j.store.DeleteObject(ctx, m.MediaKey); delErr != nil {
					// Não marca: sem o objeto apagado de verdade, a linha
					// continua vencida e o próximo tick repete.
					j.logger.Error("media_expiry_delete_object_failed", slog.String("media_id", m.ID), slog.Any("error", delErr))
					failed++
					continue
				}
				if markErr := j.media.MarkDeleted(ctx, t.ID, m.ID, now); markErr != nil {
					j.logger.Error("media_expiry_mark_failed", slog.String("media_id", m.ID), slog.Any("error", markErr))
					failed++
					continue
				}
				ok++
				deleted++
			}
			// Lote incompleto ou sem nenhum sucesso (tudo falhou): para; o
			// próximo tick continua.
			if len(due) < mediaExpiryBatch || ok == 0 {
				break
			}
		}
	}
	return deleted, failed, nil
}
