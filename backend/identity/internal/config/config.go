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
	CORSOrigins   []string
	AppEnv        string
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
		CORSOrigins:   splitAndTrim(getEnv("CORS_ORIGINS", "http://localhost:*")),
		AppEnv:        getEnv("APP_ENV", "development"),
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
