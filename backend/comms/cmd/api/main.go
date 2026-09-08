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

	"github.com/marcus-coube/lyfta/comms/internal/config"
	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/media"
	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/security"
	"github.com/marcus-coube/lyfta/comms/internal/ws"
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

	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)
	router := chttp.NewRouter(logger, cfg.CORSOrigins, verifier,
		chttp.NewConversationHandler(logger, conversations, messages, presigner, redisClient),
		chttp.NewMediaHandler(logger, conversations, presigner),
		chttp.NewWSHandler(logger, verifier, hub),
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
