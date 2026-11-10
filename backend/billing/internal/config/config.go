// Package config carrega a configuração do serviço billing a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// Config agrega as variáveis de ambiente do serviço billing. Sem
// JWT_PRIVATE_KEY (quem assina é o identity, ADR-013 §4) e sem S3_* (o
// financeiro não tem mídia).
type Config struct {
	Port          string
	DatabaseURL   string
	JWTPublicKey  string
	InternalToken string
	CORSOrigins   []string
	AppEnv        string
	// SentryDSN liga o relato de erros (ADR-009 §5); vazio = desligado.
	SentryDSN     string
	SentryRelease string
	// IdentityURL: vínculo professor↔aluno (ADR-016), cadastro do aluno e
	// configuração do tenant (ADR-017 §3) — M2M com INTERNAL_TOKEN.
	IdentityURL string
	// CoachLinkCacheTTL é o prazo do cache do vínculo (ADR-016); 0 desliga.
	CoachLinkCacheTTL time.Duration
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8085"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		CORSOrigins:   splitAndTrim(getEnv("CORS_ORIGINS", "http://localhost:*")),
		AppEnv:        getEnv("APP_ENV", "development"),
		SentryDSN:     os.Getenv("SENTRY_DSN"),
		SentryRelease: os.Getenv("SENTRY_RELEASE"),
		IdentityURL:   getEnv("IDENTITY_URL", "http://localhost:8081"),
	}

	cfg.CoachLinkCacheTTL = 30 * time.Second
	if raw := os.Getenv("COACH_LINK_CACHE_TTL"); raw != "" {
		ttl, err := time.ParseDuration(raw)
		if err != nil {
			return Config{}, fmt.Errorf("config: COACH_LINK_CACHE_TTL inválida: %w", err)
		}
		cfg.CoachLinkCacheTTL = ttl
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("config: DATABASE_URL é obrigatória")
	}
	if cfg.JWTPublicKey == "" {
		return Config{}, fmt.Errorf("config: JWT_PUBLIC_KEY é obrigatória (emitida pelo identity)")
	}
	return cfg, nil
}

// unescapeNewlines troca `\n` literal por quebra de linha real — PEMs
// distribuídos em uma única linha de env var (ver backend/scripts/gen-keys.sh).
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
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
