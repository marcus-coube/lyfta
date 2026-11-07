// Command api sobe o serviço HTTP workout (biblioteca de exercícios,
// templates/prescrição, execução e sync offline — ver backend/README.md).
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

	"github.com/marcus-coube/lyfta/workout/internal/coachlink"
	"github.com/marcus-coube/lyfta/workout/internal/config"
	whttp "github.com/marcus-coube/lyfta/workout/internal/http"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/obs"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
	"github.com/marcus-coube/lyfta/workout/internal/security"
)

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
	flushErrors, err := obs.Init("workout", cfg.SentryDSN, cfg.AppEnv, cfg.SentryRelease)
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

	exercises := repo.NewExerciseRepo(pool)
	plans := repo.NewPlanRepo(pool)
	sessions := repo.NewSessionRepo(pool)
	pending := repo.NewPendingRepo(pool)
	coachLinks := coachlink.NewClient(cfg.IdentityURL, cfg.InternalToken, cfg.CoachLinkCacheTTL)
	router := whttp.NewRouter(logger, cfg.CORSOrigins, verifier, cfg.InternalToken,
		whttp.NewMediaHandler(logger, presigner),
		whttp.NewExerciseHandler(logger, exercises, presigner),
		whttp.NewPlanHandler(logger, plans, exercises, presigner, coachLinks),
		whttp.NewSyncHandler(logger, plans, sessions, exercises, presigner, coachLinks),
		whttp.NewHistoryHandler(logger, sessions, exercises, presigner),
		whttp.NewPendingStudentsHandler(logger, pending),
		whttp.NewErasureHandler(logger, repo.NewErasureRepo(pool)),
		coachLinks,
	)

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
