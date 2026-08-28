package media_test

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/marcus-coube/lyfta/workout/internal/media"
)

const testBucket = "lyfta-media"

// storageConfig aponta para o MinIO do docker-compose (backend/docker-compose.yml).
// As credenciais são as de dev do próprio compose.
func storageConfig() media.Config {
	endpoint := os.Getenv("S3_ENDPOINT")
	if endpoint == "" {
		endpoint = "http://localhost:9000"
	}
	return media.Config{
		Endpoint:     endpoint,
		Region:       "us-east-1",
		Bucket:       testBucket,
		AccessKey:    getEnv("S3_ACCESS_KEY", "minioadmin"),
		SecretKey:    getEnv("S3_SECRET_KEY", "minioadmin"),
		UsePathStyle: true,
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// requireStorage garante MinIO no ar e o bucket criado. Fora do CI, pula
// quando o storage não responde — `go test ./...` continua rodável sem
// docker compose. No CI o MinIO é obrigatório: pular ali deixaria o pipeline
// verde sem ter exercitado o upload.
func requireStorage(t *testing.T) media.Config {
	t.Helper()
	cfg := storageConfig()
	ctx := context.Background()

	client := s3.New(s3.Options{
		Region:       cfg.Region,
		BaseEndpoint: aws.String(cfg.Endpoint),
		UsePathStyle: true,
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
	})

	_, err := client.CreateBucket(ctx, &s3.CreateBucketInput{Bucket: aws.String(cfg.Bucket)})
	if err != nil {
		var owned *types.BucketAlreadyOwnedByYou
		var exists *types.BucketAlreadyExists
		if !errors.As(err, &owned) && !errors.As(err, &exists) {
			if os.Getenv("CI") != "" {
				t.Fatalf("storage indisponível no CI: %v", err)
			}
			t.Skipf("MinIO indisponível (suba com `docker compose up -d` em backend/): %v", err)
		}
	}
	return cfg
}

// TestPresignedUploadRoundTrip cobre o Aceite do P1.2: sobe um arquivo pequeno
// no MinIO pela URL presignada e lê o mesmo conteúdo de volta.
func TestPresignedUploadRoundTrip(t *testing.T) {
	cfg := requireStorage(t)
	ctx := context.Background()

	presigner, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}

	// GIF de 1x1 transparente: arquivo pequeno, mas com bytes de verdade.
	content := []byte("GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;")
	const contentType = "image/gif"

	key, err := media.ObjectKey("22222222-2222-2222-2222-222222222222", "gif")
	if err != nil {
		t.Fatalf("montar chave: %v", err)
	}

	uploadURL, _, err := presigner.PresignPut(ctx, key, contentType, int64(len(content)))
	if err != nil {
		t.Fatalf("assinar upload: %v", err)
	}

	if status, body := doPut(t, uploadURL, contentType, content); status != http.StatusOK {
		t.Fatalf("upload deveria ser aceito, veio %d: %s", status, body)
	}

	// Leitura de volta pela URL de exibição (GET assinado: o bucket é privado).
	readURL, err := presigner.ReadURL(ctx, key)
	if err != nil {
		t.Fatalf("assinar leitura: %v", err)
	}
	resp, err := http.Get(readURL) //nolint:gosec // URL assinada gerada no próprio teste
	if err != nil {
		t.Fatalf("baixar objeto: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("esperava 200 na leitura, veio %d", resp.StatusCode)
	}
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ler corpo: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Fatalf("conteúdo lido difere do enviado (%d vs %d bytes)", len(got), len(content))
	}
	if ct := resp.Header.Get("Content-Type"); ct != contentType {
		t.Fatalf("content-type deveria ser preservado no objeto, veio %q", ct)
	}
}

// TestPresignedUploadEnforcesSignedSize prova que o teto de 50 MB é garantia
// do storage, não promessa do cliente: a URL é assinada para um tamanho e um
// content-type específicos, então subir outra coisa é recusado.
func TestPresignedUploadEnforcesSignedSize(t *testing.T) {
	cfg := requireStorage(t)
	ctx := context.Background()

	presigner, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	key, err := media.ObjectKey("22222222-2222-2222-2222-222222222222", "mp4")
	if err != nil {
		t.Fatalf("montar chave: %v", err)
	}

	// Assinada para 1024 bytes de video/mp4.
	uploadURL, _, err := presigner.PresignPut(ctx, key, "video/mp4", 1024)
	if err != nil {
		t.Fatalf("assinar upload: %v", err)
	}

	if status, _ := doPut(t, uploadURL, "video/mp4", bytes.Repeat([]byte("x"), 4096)); status == http.StatusOK {
		t.Fatal("upload maior que o tamanho assinado deveria ser recusado pelo storage")
	}
	if status, _ := doPut(t, uploadURL, "application/pdf", bytes.Repeat([]byte("x"), 1024)); status == http.StatusOK {
		t.Fatal("upload com content-type diferente do assinado deveria ser recusado pelo storage")
	}
}

// TestPresignPutRejectsBeforeSigning: o que a whitelist e o limite recusam nem
// chega a virar URL assinada.
func TestPresignPutRejectsBeforeSigning(t *testing.T) {
	presigner, err := media.NewPresigner(storageConfig())
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	ctx := context.Background()

	if _, _, err := presigner.PresignPut(ctx, "tenants/t/exercises/a.pdf", "application/pdf", 10); err == nil {
		t.Fatal("content-type fora da whitelist deveria ser recusado")
	}
	if _, _, err := presigner.PresignPut(ctx, "tenants/t/exercises/a.mp4", "video/mp4", media.MaxUploadBytes+1); err == nil {
		t.Fatal("tamanho acima de 50 MB deveria ser recusado")
	}
	if _, _, err := presigner.PresignPut(ctx, "tenants/t/exercises/a.mp4", "video/mp4", 0); err == nil {
		t.Fatal("tamanho zero deveria ser recusado")
	}
}

// TestReadURLUsesPublicBaseWhenConfigured: com CDN/domínio público
// configurado (o caso do R2 em produção), a media_url é direta e permanente
// em vez de um GET assinado que expira.
func TestReadURLUsesPublicBaseWhenConfigured(t *testing.T) {
	cfg := storageConfig()
	cfg.PublicBaseURL = "https://media.lyfta.app/"
	presigner, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}

	url, err := presigner.ReadURL(context.Background(), "tenants/t1/exercises/abc.gif")
	if err != nil {
		t.Fatalf("montar url pública: %v", err)
	}
	if url != "https://media.lyfta.app/tenants/t1/exercises/abc.gif" {
		t.Fatalf("url pública veio errada: %q", url)
	}
	if strings.Contains(url, "X-Amz-Signature") {
		t.Fatal("url pública não deveria vir assinada")
	}
}

func doPut(t *testing.T, url, contentType string, body []byte) (int, string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPut, url, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("montar PUT: %v", err)
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Content-Length", strconv.Itoa(len(body)))
	req.ContentLength = int64(len(body))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("executar PUT: %v", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(respBody)
}
