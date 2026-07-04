// Command api sobe o serviço HTTP identity (tenants, usuários, papéis,
// auth JWT, convites e recuperação de senha — ver backend/README.md).
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

	"github.com/marcus-coube/lyfta/identity/internal/config"
	ihttp "github.com/marcus-coube/lyfta/identity/internal/http"
	"github.com/marcus-coube/lyfta/identity/internal/repo"
	"github.com/marcus-coube/lyfta/identity/internal/security"
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

	jwtSigner, err := security.NewJWTSigner(cfg.JWTPrivateKey, cfg.JWTPublicKey)
	if err != nil {
		return err
	}

	tenants := repo.NewTenantRepo(pool)
	users := repo.NewUserRepo(pool)
	authRepo := repo.NewAuthRepo(pool)
	authHandler := ihttp.NewAuthHandler(logger, tenants, users, authRepo, jwtSigner)

	router := ihttp.NewRouter(logger, cfg.CORSOrigins, authHandler)

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
