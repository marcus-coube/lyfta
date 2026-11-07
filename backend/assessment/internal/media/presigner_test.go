package media_test

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"strconv"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/marcus-coube/lyfta/assessment/internal/media"
)

const testBucket = "lyfta-media"

// storageConfig aponta para o MinIO do docker-compose (backend/docker-compose.yml).
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

// requireStorage garante MinIO no ar e o bucket criado (mesmo helper do
// workout, duplicado — ADR-013 §2). Fora do CI, pula quando o storage não
// responde; no CI o MinIO é obrigatório.
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

// TestPresignedUploadRoundTrip cobre o Aceite do P2.3: sobe uma foto pequena
// no MinIO pela URL presignada e lê o mesmo conteúdo de volta.
func TestPresignedUploadRoundTrip(t *testing.T) {
	cfg := requireStorage(t)
	ctx := context.Background()

	presigner, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}

	// JPEG de 1x1 branco: arquivo pequeno, mas com bytes de verdade.
	content := []byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0xff, 0xd9}
	const contentType = "image/jpeg"

	key, err := media.ObjectKey("22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333", "jpg")
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
}

// TestPresignPutRejectsBeforeSigning: o que a whitelist e o limite recusam
// nem chega a virar URL assinada — operação offline, sem MinIO.
func TestPresignPutRejectsBeforeSigning(t *testing.T) {
	presigner, err := media.NewPresigner(storageConfig())
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	ctx := context.Background()

	if _, _, err := presigner.PresignPut(ctx, "tenants/t/students/s/photos/a.pdf", "application/pdf", 10); err == nil {
		t.Fatal("content-type fora da whitelist deveria ser recusado")
	}
	if _, _, err := presigner.PresignPut(ctx, "tenants/t/students/s/photos/a.jpg", "image/jpeg", media.MaxUploadBytes+1); err == nil {
		t.Fatal("tamanho acima de 15 MB deveria ser recusado")
	}
	if _, _, err := presigner.PresignPut(ctx, "tenants/t/students/s/photos/a.jpg", "image/jpeg", 0); err == nil {
		t.Fatal("tamanho zero deveria ser recusado")
	}
}

// TestValidKeyForStudent cobre o par de segurança do presign: a chave só é
// válida dentro da pasta do próprio tenant+aluno.
func TestValidKeyForStudent(t *testing.T) {
	const tenantID, studentID = "t1", "s1"
	key, err := media.ObjectKey(tenantID, studentID, "jpg")
	if err != nil {
		t.Fatalf("montar chave: %v", err)
	}
	if !media.ValidKeyForStudent(key, tenantID, studentID) {
		t.Fatalf("chave própria deveria ser válida: %q", key)
	}
	if media.ValidKeyForStudent(key, tenantID, "s2") {
		t.Fatal("chave de outro aluno não deveria validar")
	}
	if media.ValidKeyForStudent(key, "t2", studentID) {
		t.Fatal("chave de outro tenant não deveria validar")
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

// TestDeleteStudentObjects cobre a exclusão física da exclusão de conta
// (ADR-008 §2, P4.5): tudo na pasta do aluno some do storage — inclusive o que
// nunca foi cadastrado no banco —, a pasta de outro aluno fica intacta e
// repetir é sucesso.
func TestDeleteStudentObjects(t *testing.T) {
	cfg := requireStorage(t)
	ctx := context.Background()
	presigner, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}

	const tenantID = "44444444-4444-4444-4444-444444444444"
	const studentID, otherID = "55555555-5555-5555-5555-555555555555", "66666666-6666-6666-6666-666666666666"
	content := []byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0xff, 0xd9}

	upload := func(student string) string {
		t.Helper()
		key, err := media.ObjectKey(tenantID, student, "jpg")
		if err != nil {
			t.Fatalf("montar chave: %v", err)
		}
		url, _, err := presigner.PresignPut(ctx, key, "image/jpeg", int64(len(content)))
		if err != nil {
			t.Fatalf("assinar upload: %v", err)
		}
		if status, body := doPut(t, url, "image/jpeg", content); status != http.StatusOK {
			t.Fatalf("upload: %d %s", status, body)
		}
		return key
	}
	exists := func(key string) bool {
		t.Helper()
		url, err := presigner.ReadURL(ctx, key)
		if err != nil {
			t.Fatalf("assinar leitura: %v", err)
		}
		resp, err := http.Get(url) //nolint:gosec // URL assinada gerada no próprio teste
		if err != nil {
			t.Fatalf("GET: %v", err)
		}
		resp.Body.Close()
		return resp.StatusCode == http.StatusOK
	}

	mine1, mine2, theirs := upload(studentID), upload(studentID), upload(otherID)

	for i := 0; i < 2; i++ { // idempotente
		if err := presigner.DeleteStudentObjects(ctx, tenantID, studentID); err != nil {
			t.Fatalf("apagar (%d): %v", i+1, err)
		}
	}
	if exists(mine1) || exists(mine2) {
		t.Fatal("os objetos do aluno deveriam ter sido apagados do storage")
	}
	if !exists(theirs) {
		t.Fatal("o objeto de outro aluno não pode ser apagado")
	}
	_ = presigner.DeleteStudentObjects(ctx, tenantID, otherID)

	if err := presigner.DeleteStudentObjects(ctx, "", studentID); err == nil {
		t.Fatal("tenant vazio deveria ser recusado (prefixo amplo demais)")
	}
}
