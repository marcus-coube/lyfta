// Package media assina URLs de upload/leitura da mídia de exercício
// (ADR-010: GIF/vídeo demonstrativo) num storage S3-compatible.
//
// Os bytes nunca passam pelo serviço: o app recebe uma URL assinada e faz o
// PUT direto no storage. Em dev o storage é o MinIO do docker-compose; em
// produção é o mesmo protocolo S3 apontando para outro endpoint (ADR-009:
// "migrar para S3/R2 real é troca de endpoint").
package media

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// MaxUploadBytes é o teto de tamanho do upload (P1.2: 50 MB). O limite é
// assinado junto da URL — ver PresignPut.
const MaxUploadBytes int64 = 50 << 20

// PresignTTL é a validade das URLs assinadas: curta o suficiente para um link
// vazado não virar upload livre, longa o suficiente para um vídeo de 50 MB
// subir numa conexão ruim.
const PresignTTL = 15 * time.Minute

// AllowedType descreve um content-type aceito no upload de mídia.
type AllowedType struct {
	Extension string
	MediaType domain.MediaType
}

// allowedTypes é a whitelist do P1.2 (gif, mp4, webm). Qualquer outro
// content-type é recusado antes de assinar — a URL assinada carrega o
// content-type, então o storage recusa um upload que fuja do combinado.
var allowedTypes = map[string]AllowedType{
	"image/gif":  {Extension: "gif", MediaType: domain.MediaTypeGIF},
	"video/mp4":  {Extension: "mp4", MediaType: domain.MediaTypeVideo},
	"video/webm": {Extension: "webm", MediaType: domain.MediaTypeVideo},
}

// LookupType devolve a extensão e o tipo de mídia de um content-type aceito.
func LookupType(contentType string) (AllowedType, bool) {
	t, ok := allowedTypes[strings.ToLower(strings.TrimSpace(contentType))]
	return t, ok
}

// Config é a configuração do storage (env S3_* — ver .env.example).
type Config struct {
	Endpoint      string
	Region        string
	Bucket        string
	AccessKey     string
	SecretKey     string
	UsePathStyle  bool
	PublicBaseURL string
}

// Presigner assina URLs de upload e leitura no bucket configurado.
type Presigner struct {
	presign       *s3.PresignClient
	bucket        string
	publicBaseURL string
}

// NewPresigner monta o cliente S3 apontando para o endpoint configurado.
// Credenciais estáticas por env: o serviço não usa perfil/role da AWS, e o
// mesmo código serve MinIO, S3 e R2 (ADR-009).
func NewPresigner(cfg Config) (*Presigner, error) {
	if cfg.Endpoint == "" || cfg.Bucket == "" || cfg.AccessKey == "" || cfg.SecretKey == "" {
		return nil, fmt.Errorf("media: storage incompleto (S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY, S3_SECRET_KEY)")
	}
	region := cfg.Region
	if region == "" {
		region = "us-east-1"
	}

	client := s3.New(s3.Options{
		Region:       region,
		BaseEndpoint: aws.String(cfg.Endpoint),
		// MinIO (e o endpoint de conta do R2) servem os buckets por caminho,
		// não por subdomínio.
		UsePathStyle: cfg.UsePathStyle,
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
	})

	return &Presigner{
		presign:       s3.NewPresignClient(client),
		bucket:        cfg.Bucket,
		publicBaseURL: strings.TrimSuffix(cfg.PublicBaseURL, "/"),
	}, nil
}

// ObjectKey monta a chave do objeto no layout do P1.2:
// tenants/{tenant_id}/exercises/{uuid}.{ext} — o tenant no caminho mantém a
// mídia particionada por cliente, o que torna trivial exportar ou apagar
// tudo de um tenant (LGPD, ADR-008).
func ObjectKey(tenantID, extension string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("media: gerar id do objeto: %w", err)
	}
	return fmt.Sprintf("tenants/%s/exercises/%s.%s", tenantID, id.String(), extension), nil
}

// PresignPut assina um PUT para a chave informada.
//
// contentType e sizeBytes entram na assinatura: o upload só é aceito pelo
// storage se o cliente mandar exatamente esse Content-Type e esse
// Content-Length. É assim que o teto de 50 MB vira garantia do storage em vez
// de promessa do cliente — sem isso, a URL assinada aceitaria qualquer coisa
// de qualquer tamanho.
func (p *Presigner) PresignPut(ctx context.Context, key, contentType string, sizeBytes int64) (string, time.Time, error) {
	if sizeBytes <= 0 || sizeBytes > MaxUploadBytes {
		return "", time.Time{}, fmt.Errorf("media: tamanho fora do limite: %d", sizeBytes)
	}
	if _, ok := LookupType(contentType); !ok {
		return "", time.Time{}, fmt.Errorf("media: content-type não permitido: %q", contentType)
	}

	req, err := p.presign.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(p.bucket),
		Key:           aws.String(key),
		ContentType:   aws.String(contentType),
		ContentLength: aws.Int64(sizeBytes),
	}, s3.WithPresignExpires(PresignTTL))
	if err != nil {
		return "", time.Time{}, fmt.Errorf("media: assinar upload: %w", err)
	}
	return req.URL, time.Now().Add(PresignTTL), nil
}

// ReadURL devolve a URL de exibição da mídia.
//
// Com PublicBaseURL configurada (bucket público atrás de CDN, o caso de R2 em
// produção) devolve a URL direta e permanente. Sem ela — o caso do MinIO de
// dev, cujo bucket é privado — assina um GET temporário.
func (p *Presigner) ReadURL(ctx context.Context, key string) (string, error) {
	if p.publicBaseURL != "" {
		return p.publicBaseURL + "/" + strings.TrimPrefix(key, "/"), nil
	}

	req, err := p.presign.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(p.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(PresignTTL))
	if err != nil {
		return "", fmt.Errorf("media: assinar leitura: %w", err)
	}
	return req.URL, nil
}

// KeyFromURL extrai a chave do objeto a partir de uma URL de mídia (pública
// ou assinada) — usado a partir do P1.3, quando o coach manda de volta a
// media_url do exercício e o serviço precisa saber qual objeto ela aponta.
func KeyFromURL(rawURL, bucket string) (string, bool) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", false
	}
	path := strings.TrimPrefix(u.Path, "/")
	path = strings.TrimPrefix(path, bucket+"/")
	if !strings.HasPrefix(path, "tenants/") {
		return "", false
	}
	return path, true
}
