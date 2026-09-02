// Package config carrega a configuração do serviço assessment a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strings"
)

// Config agrega as variáveis de ambiente usadas pelo serviço assessment.
// Sem JWT_PRIVATE_KEY: quem assina token é o identity; o assessment só valida
// com a chave pública (ADR-013 §4). Sem S3 ainda: presign de foto (P2.3) é
// escopo futuro — a P2.2 é só esqueleto + schema.
type Config struct {
	Port          string
	DatabaseURL   string
	JWTPublicKey  string
	InternalToken string
	CORSOrigins   []string
	AppEnv        string
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8083"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		CORSOrigins:   splitAndTrim(getEnv("CORS_ORIGINS", "http://localhost:*")),
		AppEnv:        getEnv("APP_ENV", "development"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("config: DATABASE_URL é obrigatória")
	}
	// Sem chave pública o serviço não valida nenhum token: subiria aceitando
	// só rotas públicas e falhando em todo endpoint autenticado.
	if cfg.JWTPublicKey == "" {
		return Config{}, fmt.Errorf("config: JWT_PUBLIC_KEY é obrigatória (emitida pelo identity)")
	}

	return cfg, nil
}

// unescapeNewlines troca `\n` literal (duas runas) por quebra de linha real —
// PEMs distribuídos em uma única linha de env var (mesmo tratamento do
// identity/workout, ver backend/scripts/gen-keys.sh).
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
