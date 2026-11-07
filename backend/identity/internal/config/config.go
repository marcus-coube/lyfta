// Package config carrega a configuração do serviço identity a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strings"
)

// Config agrega as variáveis de ambiente usadas pelo serviço identity.
type Config struct {
	Port          string
	DatabaseURL   string
	JWTPublicKey  string
	JWTPrivateKey string
	InternalToken string
	ResendAPIKey  string
	MailFrom      string
	AppURL        string
	CORSOrigins   []string
	AppEnv        string
	// TermsVersion é a versão vigente dos termos de uso e da política de
	// privacidade (ADR-008 §6, P4.5). O app embarca a mesma versão em
	// assets/legal/; mudar aqui obriga todo mundo a consentir de novo.
	TermsVersion string
	// URLs dos serviços chamados na exclusão de conta (M2M, ADR-013 §5).
	WorkoutURL    string
	AssessmentURL string
	CommsURL      string
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
// JWT_PRIVATE_KEY, RESEND_API_KEY etc. são exigidas apenas pelas tarefas que
// os usam (P0.3/P0.4) — aqui apenas carregamos o que existir.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8081"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		JWTPrivateKey: unescapeNewlines(os.Getenv("JWT_PRIVATE_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		ResendAPIKey:  os.Getenv("RESEND_API_KEY"),
		MailFrom:      getEnv("MAIL_FROM", "Lyfta <no-reply@lyfta.app>"),
		AppURL:        getEnv("APP_URL", "http://localhost:5173"),
		CORSOrigins:   splitAndTrim(getEnv("CORS_ORIGINS", "http://localhost:*")),
		AppEnv:        getEnv("APP_ENV", "development"),
		TermsVersion:  getEnv("TERMS_VERSION", "2026-11-v1"),
		WorkoutURL:    getEnv("WORKOUT_URL", "http://localhost:8082"),
		AssessmentURL: getEnv("ASSESSMENT_URL", "http://localhost:8083"),
		CommsURL:      getEnv("COMMS_URL", "http://localhost:8084"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("config: DATABASE_URL é obrigatória")
	}

	return cfg, nil
}

// unescapeNewlines troca `\n` literal (duas runas) por quebra de linha real.
// PEMs de chave JWT (backend/scripts/gen-keys.sh) são distribuídos como uma
// única linha com `\n` escapado — formato comum em painéis de env var que não
// suportam multi-linha (Heroku/Render/etc.) — e precisam ser desescapados
// antes do parse (crypto/x509 espera quebras de linha reais no PEM).
func unescapeNewlines(v string) string {
	return strings.ReplaceAll(v, `\n`, "\n")
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func splitAndTrim(v string) []string {
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
