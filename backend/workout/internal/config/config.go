// Package config carrega a configuração do serviço workout a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strings"
)

// Config agrega as variáveis de ambiente usadas pelo serviço workout.
// Não há JWT_PRIVATE_KEY aqui: quem assina token é o identity; o workout só
// valida com a chave pública (ADR-013 §4).
type Config struct {
	Port          string
	DatabaseURL   string
	JWTPublicKey  string
	InternalToken string
	S3Endpoint    string
	S3Region      string
	S3Bucket      string
	S3AccessKey   string
	S3SecretKey   string
	CORSOrigins   []string
	AppEnv        string
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
// As variáveis de S3 só passam a ser exigidas na tarefa que usa mídia (P1.2);
// aqui apenas carregamos o que existir.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8082"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		S3Endpoint:    os.Getenv("S3_ENDPOINT"),
		S3Region:      getEnv("S3_REGION", "us-east-1"),
		S3Bucket:      getEnv("S3_BUCKET", "lyfta-media"),
		S3AccessKey:   os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey:   os.Getenv("S3_SECRET_KEY"),
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
// identity, ver backend/scripts/gen-keys.sh).
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
