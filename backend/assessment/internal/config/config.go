// Package config carrega a configuração do serviço assessment a partir de
// variáveis de ambiente (ver backend/.env.example e backend/README.md).
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config agrega as variáveis de ambiente usadas pelo serviço assessment.
// Sem JWT_PRIVATE_KEY: quem assina token é o identity; o assessment só valida
// com a chave pública (ADR-013 §4). S3_* entra na P2.3 junto do presign de
// foto de evolução — dívida anotada na P2.2, quitada aqui.
type Config struct {
	Port            string
	DatabaseURL     string
	JWTPublicKey    string
	InternalToken   string
	S3Endpoint      string
	S3Region        string
	S3Bucket        string
	S3AccessKey     string
	S3SecretKey     string
	S3UsePathStyle  bool
	S3PublicBaseURL string
	CORSOrigins     []string
	AppEnv          string
	// IdentityURL é onde o assessment consulta o consentimento de OUTRA
	// pessoa (coach lendo fotos do aluno, P4.5) — M2M com INTERNAL_TOKEN.
	IdentityURL string
}

// Load lê as variáveis de ambiente do processo e valida as obrigatórias.
func Load() (Config, error) {
	cfg := Config{
		Port:          getEnv("PORT", "8083"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		JWTPublicKey:  unescapeNewlines(os.Getenv("JWT_PUBLIC_KEY")),
		InternalToken: os.Getenv("INTERNAL_TOKEN"),
		S3Endpoint:    os.Getenv("S3_ENDPOINT"),
		S3Region:      getEnv("S3_REGION", "us-east-1"),
		S3Bucket:      getEnv("S3_BUCKET", "lyfta-media"),
		S3AccessKey:   os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey:   os.Getenv("S3_SECRET_KEY"),
		// MinIO e o endpoint de conta do R2 servem bucket por caminho; um S3
		// "de verdade" usa subdomínio (S3_USE_PATH_STYLE=false) — mesmo
		// critério do workout (P1.2).
		S3UsePathStyle:  getEnvBool("S3_USE_PATH_STYLE", true),
		S3PublicBaseURL: os.Getenv("S3_PUBLIC_BASE_URL"),
		CORSOrigins:     splitAndTrim(getEnv("CORS_ORIGINS", "http://localhost:*")),
		AppEnv:          getEnv("APP_ENV", "development"),
		IdentityURL:     getEnv("IDENTITY_URL", "http://localhost:8081"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("config: DATABASE_URL é obrigatória")
	}
	// Sem chave pública o serviço não valida nenhum token: subiria aceitando
	// só rotas públicas e falhando em todo endpoint autenticado.
	if cfg.JWTPublicKey == "" {
		return Config{}, fmt.Errorf("config: JWT_PUBLIC_KEY é obrigatória (emitida pelo identity)")
	}
	// Foto de evolução (P2.3) é parte do serviço: sem storage configurado o
	// upload falharia só na hora do uso, com o aluno/coach na frente da tela.
	for _, v := range []struct{ name, value string }{
		{"S3_ENDPOINT", cfg.S3Endpoint},
		{"S3_BUCKET", cfg.S3Bucket},
		{"S3_ACCESS_KEY", cfg.S3AccessKey},
		{"S3_SECRET_KEY", cfg.S3SecretKey},
	} {
		if v.value == "" {
			return Config{}, fmt.Errorf("config: %s é obrigatória (storage da foto de evolução)", v.name)
		}
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

// getEnvBool aceita os valores que strconv.ParseBool entende ("1", "true",
// "false"…); qualquer outra coisa cai no fallback.
func getEnvBool(key string, fallback bool) bool {
	v, ok := os.LookupEnv(key)
	if !ok || v == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return parsed
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
