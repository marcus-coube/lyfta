// Command api sobe o serviço HTTP billing (planos de mensalidade,
// assinaturas, faturas e baixa manual — ver backend/README.md).
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

	"github.com/marcus-coube/lyfta/billing/internal/coachlink"
	"github.com/marcus-coube/lyfta/billing/internal/config"
	ahttp "github.com/marcus-coube/lyfta/billing/internal/http"
	"github.com/marcus-coube/lyfta/billing/internal/job"
	"github.com/marcus-coube/lyfta/billing/internal/obs"
	"github.com/marcus-coube/lyfta/billing/internal/repo"
	"github.com/marcus-coube/lyfta/billing/internal/security"
	"github.com/marcus-coube/lyfta/billing/internal/studentdir"
	"github.com/marcus-coube/lyfta/billing/internal/tenantclient"
	"github.com/marcus-coube/lyfta/billing/internal/tenantsettings"
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
	flushErrors, err := obs.Init("billing", cfg.SentryDSN, cfg.AppEnv, cfg.SentryRelease)
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

	billing := ahttp.NewBillingHandler(logger,
		repo.NewPlanRepo(pool), repo.NewSubscriptionRepo(pool), repo.NewInvoiceRepo(pool), repo.NewErasureRepo(pool),
		tenantsettings.NewClient(cfg.IdentityURL, cfg.InternalToken, cfg.TenantSettingsCacheTTL),
		studentdir.NewClient(cfg.IdentityURL, cfg.InternalToken),
		coachlink.NewClient(cfg.IdentityURL, cfg.InternalToken, cfg.CoachLinkCacheTTL),
		nil)
	router := ahttp.NewRouter(logger, cfg.CORSOrigins, verifier, cfg.InternalToken, billing)

	// Geração mensal e vencimento (P7.3), no fuso de cada tenant.
	monthly := job.NewMonthlyJob(logger, pool,
		tenantclient.NewClient(cfg.IdentityURL, cfg.InternalToken, tenantclient.DefaultTTL),
		repo.NewJobRepo(pool))
	go monthly.Run(ctx)

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
