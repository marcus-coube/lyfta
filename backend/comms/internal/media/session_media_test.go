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

	"github.com/marcus-coube/duo/comms/internal/media"
)

func storageConfig() media.Config {
	endpoint := os.Getenv("S3_ENDPOINT")
	if endpoint == "" {
		endpoint = "http://localhost:9000"
	}
	return media.Config{
		Endpoint: endpoint, Region: "us-east-1", Bucket: "duo-media",
		AccessKey: getEnv("S3_ACCESS_KEY", "minioadmin"), SecretKey: getEnv("S3_SECRET_KEY", "minioadmin"),
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
// assessment, duplicado — ADR-013 §2). Fora do CI pula quando o storage não
// responde; no CI o MinIO é obrigatório.
func requireStorage(t *testing.T) media.Config {
	t.Helper()
	cfg := storageConfig()
	client := s3.New(s3.Options{
		Region: cfg.Region, BaseEndpoint: aws.String(cfg.Endpoint), UsePathStyle: true,
		Credentials: credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, ""),
	})
	_, err := client.CreateBucket(context.Background(), &s3.CreateBucketInput{Bucket: aws.String(cfg.Bucket)})
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

func put(t *testing.T, url, contentType string, body []byte) int {
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
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode
}

func TestPresignSessionMediaRejectsBeforeSigning(t *testing.T) {
	p, err := media.NewPresigner(storageConfig())
	if err != nil {
		t.Fatalf("presigner: %v", err)
	}
	ctx := context.Background()
	if _, _, err := p.PresignSessionMediaPut(ctx, "k.mp4", "video/mp4", media.MaxSessionMediaBytes+1); err == nil {
		t.Fatal("acima de 20 MB deveria ser recusado")
	}
	if _, _, err := p.PresignSessionMediaPut(ctx, "k.mp4", "video/mp4", media.MaxSessionMediaBytes); err != nil {
		t.Fatalf("exatamente 20 MB é permitido: %v", err)
	}
	if _, _, err := p.PresignSessionMediaPut(ctx, "k.pdf", "application/pdf", 10); err == nil {
		t.Fatal("tipo fora da whitelist deveria ser recusado")
	}
	for _, ct := range []string{"video/mp4", "video/quicktime", "video/webm", "image/jpeg", "image/png", "image/webp"} {
		if _, ok := media.LookupSessionMediaType(ct); !ok {
			t.Fatalf("%s deveria ser aceito", ct)
		}
	}
}

func TestValidSessionMediaKey(t *testing.T) {
	const tenant, student, session = "t1", "s1", "c1"
	key, err := media.SessionMediaKey(tenant, student, session, "mp4")
	if err != nil {
		t.Fatalf("chave: %v", err)
	}
	if !media.ValidSessionMediaKey(key, tenant, student, session) {
		t.Fatalf("chave própria deveria validar: %s", key)
	}
	if media.ValidSessionMediaKey(key, tenant, "s2", session) || media.ValidSessionMediaKey(key, "t2", student, session) ||
		media.ValidSessionMediaKey(key, tenant, student, "c2") {
		t.Fatal("chave de outro aluno, tenant ou sessão não deveria validar")
	}
}

// TestSessionMediaStorageRoundTrip exercita contra o MinIO: PUT presignado,
// HEAD (tamanho/tipo reais), leitura assinada, DeleteObject idempotente e
// DeleteStudentObjects (só a pasta session-media do aluno; as fotos de
// evolução do assessment, vizinhas na árvore, ficam).
func TestSessionMediaStorageRoundTrip(t *testing.T) {
	cfg := requireStorage(t)
	ctx := context.Background()
	p, err := media.NewPresigner(cfg)
	if err != nil {
		t.Fatalf("presigner: %v", err)
	}

	const tenant = "77777777-7777-7777-7777-777777777777"
	const student, other = "88888888-8888-8888-8888-888888888888", "99999999-9999-9999-9999-999999999999"
	const session = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	content := []byte("fake-mp4-bytes")

	upload := func(studentID, key string) {
		t.Helper()
		url, _, err := p.PresignSessionMediaPut(ctx, key, "video/mp4", int64(len(content)))
		if err != nil {
			t.Fatalf("assinar: %v", err)
		}
		if status := put(t, url, "video/mp4", content); status != http.StatusOK {
			t.Fatalf("upload: %d", status)
		}
	}
	key, _ := media.SessionMediaKey(tenant, student, session, "mp4")
	key2, _ := media.SessionMediaKey(tenant, student, session, "mp4")
	otherKey, _ := media.SessionMediaKey(tenant, other, session, "mp4")
	photoKey := "tenants/" + tenant + "/students/" + student + "/photos/keep.jpg"
	upload(student, key)
	upload(student, key2)
	upload(other, otherKey)
	// foto de evolução do assessment: precisa sobreviver
	purl, _, _ := p.PresignPut(ctx, photoKey, "image/jpeg", 3)
	if status := put(t, purl, "image/jpeg", []byte("jpg")); status != http.StatusOK {
		t.Fatalf("upload da foto: %d", status)
	}

	info, err := p.Head(ctx, key)
	if err != nil || info.SizeBytes != int64(len(content)) || info.ContentType != "video/mp4" {
		t.Fatalf("HEAD: %+v err=%v", info, err)
	}
	if _, err := p.Head(ctx, key+".nao-existe"); !errors.Is(err, media.ErrObjectNotFound) {
		t.Fatalf("HEAD de objeto inexistente deveria ser ErrObjectNotFound, veio %v", err)
	}

	readURL, err := p.SignedReadURL(ctx, key)
	if err != nil {
		t.Fatalf("leitura assinada: %v", err)
	}
	resp, err := http.Get(readURL) //nolint:gosec // URL assinada gerada no próprio teste
	if err != nil {
		t.Fatalf("baixar: %v", err)
	}
	got, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK || !bytes.Equal(got, content) {
		t.Fatalf("leitura assinada: %d %q", resp.StatusCode, got)
	}

	if err := p.DeleteObject(ctx, key); err != nil {
		t.Fatalf("apagar objeto: %v", err)
	}
	if err := p.DeleteObject(ctx, key); err != nil {
		t.Fatalf("apagar objeto de novo deveria ser sucesso: %v", err)
	}
	if _, err := p.Head(ctx, key); !errors.Is(err, media.ErrObjectNotFound) {
		t.Fatalf("o objeto deveria ter sumido, veio %v", err)
	}

	for i := 0; i < 2; i++ { // idempotente
		if err := p.DeleteStudentObjects(ctx, tenant, student); err != nil {
			t.Fatalf("apagar pasta do aluno (%d): %v", i+1, err)
		}
	}
	if _, err := p.Head(ctx, key2); !errors.Is(err, media.ErrObjectNotFound) {
		t.Fatalf("a mídia do aluno deveria ter sumido, veio %v", err)
	}
	if _, err := p.Head(ctx, otherKey); err != nil {
		t.Fatalf("a mídia de outro aluno não pode ser tocada: %v", err)
	}
	if _, err := p.Head(ctx, photoKey); err != nil {
		t.Fatalf("a foto de evolução (assessment) não pode ser tocada: %v", err)
	}
	_ = p.DeleteObject(ctx, otherKey)
	_ = p.DeleteObject(ctx, photoKey)
}
