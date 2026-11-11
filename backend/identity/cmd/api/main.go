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
	_ "time/tzdata" // fuso IANA sem depender do tzdata do SO (P5.1)

	"github.com/marcus-coube/lyfta/identity/internal/config"
	"github.com/marcus-coube/lyfta/identity/internal/erasure"
	ihttp "github.com/marcus-coube/lyfta/identity/internal/http"
	"github.com/marcus-coube/lyfta/identity/internal/mail"
	"github.com/marcus-coube/lyfta/identity/internal/obs"
	"github.com/marcus-coube/lyfta/identity/internal/ratelimit"
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

	// DSN vazio = desligado (P4.6): nenhum evento sai do processo.
	flushErrors, err := obs.Init("identity", cfg.SentryDSN, cfg.AppEnv, cfg.SentryRelease)
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

	jwtSigner, err := security.NewJWTSigner(cfg.JWTPrivateKey, cfg.JWTPublicKey)
	if err != nil {
		return err
	}

	// Sem RESEND_API_KEY (dev/teste): loga o link do e-mail no stdout em vez de
	// enviar de verdade, para o fluxo de convite/reset ser exercitável sem
	// depender de e-mail real (Aceite do P0.4).
	var mailer mail.Mailer
	if cfg.ResendAPIKey == "" {
		logger.Warn("mail_using_log_mailer", slog.String("reason", "RESEND_API_KEY vazio"))
		mailer = mail.NewLogMailer(logger)
	} else {
		mailer = mail.NewResendMailer(cfg.ResendAPIKey, cfg.MailFrom)
	}

	tenants := repo.NewTenantRepo(pool)
	users := repo.NewUserRepo(pool)
	authRepo := repo.NewAuthRepo(pool)
	invitationRepo := repo.NewInvitationRepo(pool)
	passwordResetRepo := repo.NewPasswordResetRepo(pool)
	consentRepo := repo.NewConsentRepo(pool)

	issuer := ihttp.NewSessionIssuer(logger, jwtSigner, authRepo, consentRepo, tenants, cfg.TermsVersion)
	eraser := erasure.New(cfg.InternalToken, []erasure.Target{
		{Name: "assessment", BaseURL: cfg.AssessmentURL},
		{Name: "workout", BaseURL: cfg.WorkoutURL},
		{Name: "comms", BaseURL: cfg.CommsURL},
		{Name: "billing", BaseURL: cfg.BillingURL, Profile: true},
	}).WithBilling(cfg.BillingURL)

	authHandler := ihttp.NewAuthHandler(logger, tenants, users, authRepo, issuer, cfg.TermsVersion)
	invitationHandler := ihttp.NewInvitationHandler(logger, invitationRepo, tenants, users, consentRepo, repo.NewCoachLinkRepo(pool), issuer, mailer, cfg.AppURL, cfg.TermsVersion)
	accountHandler := ihttp.NewAccountHandler(logger, users, authRepo, consentRepo, issuer, eraser, cfg.TermsVersion)
	passwordResetHandler := ihttp.NewPasswordResetHandler(logger, authRepo, users, passwordResetRepo, mailer, cfg.AppURL)

	// Limite de tentativas dos endpoints públicos (ADR-002 §2c). Sem
	// REDIS_URL (dev): contadores em memória, válidos só nesta instância.
	var limitStore ratelimit.Store
	if cfg.RedisURL == "" {
		logger.Warn("rate_limit_using_memory_store", slog.String("reason", "REDIS_URL vazio"))
		limitStore = ratelimit.NewMemoryStore()
	} else {
		redisStore, err := ratelimit.NewRedisStore(ctx, cfg.RedisURL)
		if err != nil {
			return err
		}
		defer func() { _ = redisStore.Close() }()
		limitStore = redisStore
	}
	limiter := ihttp.NewRateLimiter(limitStore, logger, cfg.TrustProxy)

	userHandler := ihttp.NewUserHandler(logger, users, repo.NewCoachLinkRepo(pool))
	router := ihttp.NewRouter(logger, cfg.CORSOrigins, jwtSigner, cfg.InternalToken, authHandler, invitationHandler, passwordResetHandler, userHandler, accountHandler, ihttp.NewTenantHandler(logger, tenants), ihttp.NewStudentHandler(logger, users, repo.NewStudentRepo(pool), repo.NewCoachLinkRepo(pool)), limiter)

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
