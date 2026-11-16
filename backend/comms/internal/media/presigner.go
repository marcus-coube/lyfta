// Package media assina URLs de upload/leitura da imagem de chat (ADR-012 §2)
// num storage S3-compatible.
//
// Os bytes nunca passam pelo serviço: o app recebe uma URL assinada e faz o
// PUT direto no storage. Irmão do internal/media do workout (P1.2) e do
// assessment (P2.3), duplicado de propósito — serviços não importam código
// uns dos outros (ADR-013 §2). A diferença de layout: a chave carrega a
// conversa, não o aluno — tenants/{t}/chat/{conversation_id}/{uuid}.ext —
// porque a mídia pertence à conversa (ambos os participantes podem enviar),
// não a um único usuário.
package media

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/google/uuid"
)

// MaxUploadBytes é o teto de tamanho do upload (imagem de chat, não vídeo —
// ADR-012 §2 restringe o MVP a texto+imagem). Mesmo teto do P2.3.
const MaxUploadBytes int64 = 15 << 20

// PresignTTL é a validade das URLs assinadas — mesmo critério dos demais
// serviços: curta o bastante para um link vazado não virar upload livre,
// longa o bastante para subir numa conexão ruim.
const PresignTTL = 15 * time.Minute

// allowedTypes é a whitelist de formatos aceitos — os que `image_picker`/
// câmera do app produzem (reusa a infra do P2.4).
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
	client        *s3.Client
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
		client:        client,
		presign:       s3.NewPresignClient(client),
		bucket:        cfg.Bucket,
		publicBaseURL: strings.TrimSuffix(cfg.PublicBaseURL, "/"),
	}, nil
}

// ObjectKey monta a chave do objeto no layout do P3.2:
// tenants/{tenant_id}/chat/{conversation_id}/{uuid}.{ext}.
func ObjectKey(tenantID, conversationID, extension string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("media: gerar id do objeto: %w", err)
	}
	return fmt.Sprintf("tenants/%s/chat/%s/%s.%s", tenantID, conversationID, id.String(), extension), nil
}

// ValidKeyForConversation confirma que key aponta para a pasta da conversa
// dentro do tenant — o par de segurança do presign: sem isso um participante
// poderia anexar numa mensagem uma key apontando para a pasta de outra
// conversa (inclusive de outro tenant).
func ValidKeyForConversation(key, tenantID, conversationID string) bool {
	return strings.HasPrefix(key, fmt.Sprintf("tenants/%s/chat/%s/", tenantID, conversationID))
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
	return p.presignPut(ctx, key, contentType, sizeBytes)
}

func (p *Presigner) presignPut(ctx context.Context, key, contentType string, sizeBytes int64) (string, time.Time, error) {
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

// --- Mídia de execução (ADR-020, P12.1) ---------------------------------
//
// Vídeo ou foto que o aluno anexa ao treino para o professor avaliar. Mora
// em tenants/{t}/students/{s}/session-media/{session_client_id}/{uuid}.ext —
// a mesma árvore tenants/{t}/students/{s}/ do assessment (fotos de evolução),
// mas em subpasta própria: a exclusão de conta do comms só pode apagar o que é
// dele.

// MaxSessionMediaBytes é o teto da mídia de execução (ADR-020 §2): 20 MB,
// garantido na assinatura do PUT e conferido de novo com HEAD no registro.
const MaxSessionMediaBytes int64 = 20 << 20

var sessionMediaTypes = map[string]string{
	"video/mp4":       "mp4",
	"video/quicktime": "mov",
	"video/webm":      "webm",
	"image/jpeg":      "jpg",
	"image/png":       "png",
	"image/webp":      "webp",
}

// LookupSessionMediaType devolve a extensão de um content-type aceito na
// mídia de execução.
func LookupSessionMediaType(contentType string) (string, bool) {
	ext, ok := sessionMediaTypes[strings.ToLower(strings.TrimSpace(contentType))]
	return ext, ok
}

// SessionMediaKey monta a chave de uma mídia de execução.
func SessionMediaKey(tenantID, studentID, sessionClientID, extension string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("media: gerar id do objeto: %w", err)
	}
	return fmt.Sprintf("%s%s/%s.%s", StudentSessionMediaPrefix(tenantID, studentID), sessionClientID, id.String(), extension), nil
}

// StudentSessionMediaPrefix é a pasta da mídia de execução de um aluno.
func StudentSessionMediaPrefix(tenantID, studentID string) string {
	return fmt.Sprintf("tenants/%s/students/%s/session-media/", tenantID, studentID)
}

// ValidSessionMediaKey confirma que key aponta para a pasta da sessão do
// próprio aluno no tenant — o par de segurança do presign.
func ValidSessionMediaKey(key, tenantID, studentID, sessionClientID string) bool {
	return strings.HasPrefix(key, StudentSessionMediaPrefix(tenantID, studentID)+sessionClientID+"/")
}

// PresignSessionMediaPut assina o PUT de uma mídia de execução (até 20 MB;
// tipo e tamanho entram na assinatura).
func (p *Presigner) PresignSessionMediaPut(ctx context.Context, key, contentType string, sizeBytes int64) (string, time.Time, error) {
	if sizeBytes <= 0 || sizeBytes > MaxSessionMediaBytes {
		return "", time.Time{}, fmt.Errorf("media: tamanho fora do limite: %d", sizeBytes)
	}
	if _, ok := LookupSessionMediaType(contentType); !ok {
		return "", time.Time{}, fmt.Errorf("media: content-type não permitido: %q", contentType)
	}
	return p.presignPut(ctx, key, contentType, sizeBytes)
}

// SignedReadURL assina um GET curto SEMPRE, mesmo com PublicBaseURL: a mídia
// de execução nunca é pública (ADR-020 §2).
func (p *Presigner) SignedReadURL(ctx context.Context, key string) (string, error) {
	if key == "" {
		return "", nil
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

// ErrObjectNotFound: o objeto não existe no storage (upload não feito ou já
// apagado).
var ErrObjectNotFound = errors.New("media: objeto não encontrado")

// ObjectInfo é o que o HEAD revela do objeto.
type ObjectInfo struct {
	SizeBytes   int64
	ContentType string
}

// Head confere o objeto no storage — o registro da mídia usa o tamanho e o
// tipo reais, não os declarados pelo cliente.
func (p *Presigner) Head(ctx context.Context, key string) (ObjectInfo, error) {
	out, err := p.client.HeadObject(ctx, &s3.HeadObjectInput{Bucket: aws.String(p.bucket), Key: aws.String(key)})
	if err != nil {
		var notFound *types.NotFound
		if errors.As(err, &notFound) {
			return ObjectInfo{}, ErrObjectNotFound
		}
		return ObjectInfo{}, fmt.Errorf("media: head do objeto: %w", err)
	}
	return ObjectInfo{SizeBytes: aws.ToInt64(out.ContentLength), ContentType: aws.ToString(out.ContentType)}, nil
}

// DeleteObject apaga fisicamente um objeto. Idempotente: S3 responde sucesso
// para chave inexistente.
func (p *Presigner) DeleteObject(ctx context.Context, key string) error {
	if key == "" {
		return nil
	}
	if _, err := p.client.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(p.bucket), Key: aws.String(key)}); err != nil {
		return fmt.Errorf("media: apagar %s: %w", key, err)
	}
	return nil
}

// DeleteStudentObjects apaga fisicamente TODA a mídia de execução do aluno
// (exclusão de conta, ADR-008 §2): lista pela pasta em vez de confiar nas
// linhas do banco, então pega também upload nunca registrado. Idempotente.
func (p *Presigner) DeleteStudentObjects(ctx context.Context, tenantID, studentID string) error {
	if tenantID == "" || studentID == "" {
		return fmt.Errorf("media: tenant e aluno são obrigatórios para apagar a pasta")
	}
	prefix := StudentSessionMediaPrefix(tenantID, studentID)

	var token *string
	for {
		page, err := p.client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
			Bucket:            aws.String(p.bucket),
			Prefix:            aws.String(prefix),
			ContinuationToken: token,
		})
		if err != nil {
			return fmt.Errorf("media: listar objetos do aluno: %w", err)
		}
		for _, obj := range page.Contents {
			if _, err := p.client.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(p.bucket), Key: obj.Key}); err != nil {
				return fmt.Errorf("media: apagar %s: %w", aws.ToString(obj.Key), err)
			}
		}
		if !aws.ToBool(page.IsTruncated) {
			return nil
		}
		token = page.NextContinuationToken
	}
}
