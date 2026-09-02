// Package media assina URLs de upload/leitura das fotos de evolução
// (ADR-012 §2) num storage S3-compatible.
//
// Os bytes nunca passam pelo serviço: o app recebe uma URL assinada e faz o
// PUT direto no storage. Irmão do internal/media do workout (P1.2),
// duplicado de propósito — serviços não importam código uns dos outros
// (ADR-013 §2). A diferença de layout: a chave da foto carrega o aluno, não
// só o tenant (tenants/{t}/students/{s}/photos/{uuid}.ext), porque a foto é
// um fato pessoal do aluno, não um recurso compartilhado do tenant como o
// exercício.
package media

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
)

// MaxUploadBytes é o teto de tamanho do upload (P2.3: 15 MB — foto, não
// vídeo). O limite é assinado junto da URL — ver PresignPut.
const MaxUploadBytes int64 = 15 << 20

// PresignTTL é a validade das URLs assinadas: mesmo critério do workout —
// curta o bastante para um link vazado não virar upload livre, longa o
// bastante para subir numa conexão ruim.
const PresignTTL = 15 * time.Minute

// allowedTypes é a whitelist do P2.3: jpeg, png, webp — os formatos que
// `image_picker`/câmera do app produzem (P2.4).
var allowedTypes = map[string]string{
	"image/jpeg": "jpg",
	"image/png":  "png",
	"image/webp": "webp",
}

// LookupType devolve a extensão de um content-type aceito.
func LookupType(contentType string) (string, bool) {
	ext, ok := allowedTypes[strings.ToLower(strings.TrimSpace(contentType))]
	return ext, ok
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
		UsePathStyle: cfg.UsePathStyle,
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
	})

	return &Presigner{
		presign:       s3.NewPresignClient(client),
		bucket:        cfg.Bucket,
		publicBaseURL: strings.TrimSuffix(cfg.PublicBaseURL, "/"),
	}, nil
}

// ObjectKey monta a chave do objeto no layout do P2.3:
// tenants/{tenant_id}/students/{student_id}/photos/{uuid}.{ext}.
func ObjectKey(tenantID, studentID, extension string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("media: gerar id do objeto: %w", err)
	}
	return fmt.Sprintf("tenants/%s/students/%s/photos/%s.%s", tenantID, studentID, id.String(), extension), nil
}

// ValidKeyForStudent confirma que key aponta para a pasta do aluno dentro do
// tenant — o par de segurança do presign: sem isso um aluno (ou coach)
// poderia cadastrar uma foto apontando para a pasta de outro aluno.
func ValidKeyForStudent(key, tenantID, studentID string) bool {
	return strings.HasPrefix(key, fmt.Sprintf("tenants/%s/students/%s/photos/", tenantID, studentID))
}

// PresignPut assina um PUT para a chave informada. contentType e sizeBytes
// entram na assinatura, então o teto de 15 MB é garantia do storage.
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

// ReadURL devolve a URL de exibição da mídia. Com PublicBaseURL configurada
// (bucket público atrás de CDN) devolve a URL direta e permanente; sem ela —
// o caso do MinIO de dev — assina um GET temporário.
func (p *Presigner) ReadURL(ctx context.Context, key string) (string, error) {
	if key == "" {
		return "", nil
	}
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
