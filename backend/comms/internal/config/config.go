// Package config carrega a configuração do serviço comms a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strings"
)

// Config agrega as variáveis de ambiente usadas pelo serviço comms.
// Sem JWT_PRIVATE_KEY: quem assina token é o identity; o comms só valida com
// a chave pública (ADR-013 §4). S3_* entra na P3.2 junto do presign de imagem
// do chat — não é obrigatória aqui porque a P3.1 não expõe nenhum endpoint de
// mídia (mesma progressão do assessment: dívida anotada, quitada quando o
// endpoint existir).
type Config struct {
	Port          string
	DatabaseURL   string
	JWTPublicKey  string
	InternalToken string
	RedisURL      string
	CORSOrigins   []string
	AppEnv        string
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8084"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		RedisURL:      getEnv("REDIS_URL", "redis://localhost:6379/0"),
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
	// Fan-out de WS entre instâncias (P3.2) depende do Redis — sem ele o
	// serviço subiria e só falharia na primeira mensagem em trânsito.
	if cfg.RedisURL == "" {
		return Config{}, fmt.Errorf("config: REDIS_URL é obrigatória")
	}

	return cfg, nil
}

// unescapeNewlines troca `\n` literal (duas runas) por quebra de linha real —
// PEMs distribuídos em uma única linha de env var (mesmo tratamento do
// identity/workout/assessment, ver backend/scripts/gen-keys.sh).
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
