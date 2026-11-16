// Command api sobe o serviço HTTP comms (chat, check-in de treino, push —
// ver backend/README.md).
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // fuso IANA sem depender do tzdata do SO (P5.1)

	"github.com/marcus-coube/duo/comms/internal/coachlink"
	"github.com/marcus-coube/duo/comms/internal/config"
	"github.com/marcus-coube/duo/comms/internal/fcm"
	chttp "github.com/marcus-coube/duo/comms/internal/http"
	"github.com/marcus-coube/duo/comms/internal/job"
	"github.com/marcus-coube/duo/comms/internal/media"
	"github.com/marcus-coube/duo/comms/internal/obs"
	"github.com/marcus-coube/duo/comms/internal/pubsub"
	"github.com/marcus-coube/duo/comms/internal/push"
	"github.com/marcus-coube/duo/comms/internal/repo"
	"github.com/marcus-coube/duo/comms/internal/security"
	"github.com/marcus-coube/duo/comms/internal/tenantclient"
	"github.com/marcus-coube/duo/comms/internal/workoutclient"
	"github.com/marcus-coube/duo/comms/internal/ws"
)

// pendingWorkoutTriggerHour é a hora (0-23) a partir da qual o job diário
// considera o dia fechado para quem ainda não treinou — "até as 18h locais"
// do plano (P3.4, passo 3).
const pendingWorkoutTriggerHour = 18

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	if err := run(logger); err != nil {
		logger.Error("service_failed", slog.Any("error", err))
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	// DSN vazio = desligado (P4.6): nenhum evento sai do processo.
	flushErrors, err := obs.Init("comms", cfg.SentryDSN, cfg.AppEnv, cfg.SentryRelease)
	if err != nil {
		return err
	}
	defer flushErrors()
	if cfg.SentryDSN == "" {
		logger.Info("error_reporting_disabled", slog.String("reason", "SENTRY_DSN vazio"))
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool, err := repo.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	// Fan-out de WS entre instâncias (P3.2) — nasce configurado mesmo com uma
	// única instância hoje (ver internal/pubsub).
	redisClient, err := pubsub.NewClient(ctx, cfg.RedisURL)
	if err != nil {
		return err
	}
	defer func() { _ = redisClient.Close() }()

	// Só valida: a chave privada que assina os tokens vive no identity
	// (ADR-013 §4).
	verifier, err := security.NewJWTVerifier(cfg.JWTPublicKey)
	if err != nil {
		return err
	}

	presigner, err := media.NewPresigner(media.Config{
		Endpoint:      cfg.S3Endpoint,
		Region:        cfg.S3Region,
		Bucket:        cfg.S3Bucket,
		AccessKey:     cfg.S3AccessKey,
		SecretKey:     cfg.S3SecretKey,
		UsePathStyle:  cfg.S3UsePathStyle,
		PublicBaseURL: cfg.S3PublicBaseURL,
	})
	if err != nil {
		return err
	}

	// Registro das conexões WS ativas nesta instância (P3.2) — o
	// pubsub.Relay entrega aqui o que os handlers REST publicam no Redis
	// (fan-out entre instâncias, mesmo com uma única instância hoje).
	hub := ws.NewHub()
	go pubsub.Relay(ctx, redisClient, logger, hub.Deliver)

	// Push FCM (P3.4). Sem credencial configurada, o serviço sobe do mesmo
	// jeito — chat e check-in não dependem de push — só com push desligado
	// (Notifier com pusher nil: loga e não faz nada). Com credencial
	// inválida, falha cedo, mesmo critério do resto da config.
	var pusher push.Pusher
	if cfg.FCMCredentialsJSON == "" {
		logger.Warn("push_disabled", slog.String("reason", "FCM_CREDENTIALS_JSON não configurada"))
	} else {
		fcmClient, err := fcm.NewClient(ctx, cfg.FCMCredentialsJSON)
		if err != nil {
			return err
		}
		pusher = fcmClient
	}

	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)
	checkins := repo.NewCheckinRepo(pool)
	deviceTokens := repo.NewDeviceTokenRepo(pool)
	notifications := repo.NewNotificationLogRepo(pool)
	notifier := push.NewNotifier(logger, deviceTokens, notifications, pusher)

	coachLinks := coachlink.NewClient(cfg.IdentityURL, cfg.InternalToken, cfg.CoachLinkCacheTTL)
	sessionMedia := repo.NewSessionMediaRepo(pool)
	conversationHandler := chttp.NewConversationHandler(logger, conversations, messages, presigner, redisClient, notifier, coachLinks)

	router := chttp.NewRouter(logger, cfg.CORSOrigins, verifier, cfg.InternalToken,
		conversationHandler,
		chttp.NewMediaHandler(logger, conversations, presigner, coachLinks),
		chttp.NewWSHandler(logger, verifier, hub, redisClient),
		chttp.NewCheckinHandler(logger, checkins, coachLinks, redisClient, notifier).WithSessionMedia(sessionMedia),
		chttp.NewDeviceHandler(logger, deviceTokens),
		chttp.NewErasureHandler(logger, repo.NewErasureRepo(pool), presigner),
		chttp.NewSessionMediaHandler(logger, sessionMedia, presigner, coachLinks, conversations, conversationHandler, notifier),
	)

	// Job diário "treino pendente" (P3.4, passo 3) — M2M com o workout
	// (ADR-013 §4/§5), dedupe por notification_log e pg_advisory_lock contra
	// duas instâncias rodando ao mesmo tempo (ver internal/job).
	workoutClient := workoutclient.NewClient(cfg.WorkoutBaseURL, cfg.InternalToken)
	tenantClient := tenantclient.NewClient(cfg.IdentityURL, cfg.InternalToken, tenantclient.DefaultTTL)
	pendingJob := job.NewPendingWorkoutJob(logger, pool, workoutClient, tenantClient, coachLinks, notifications, notifier, pendingWorkoutTriggerHour)
	go pendingJob.Run(ctx)

	// Expiração da mídia de execução (ADR-020, P12.1): mesmo advisory lock do
	// job acima, um tick a cada 5 min.
	go job.NewMediaExpiryJob(logger, pool, sessionMedia, presigner, tenantClient).Run(ctx)

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	errCh := make(chan error, 1)
	go func() {
		logger.Info("service_starting", slog.String("port", cfg.Port))
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case <-stop:
		logger.Info("service_stopping")
	case err := <-errCh:
		return err
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	return server.Shutdown(shutdownCtx)
}
