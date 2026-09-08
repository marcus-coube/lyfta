package pubsub_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
)

// testRedisURL usa o mesmo default documentado em backend/.env.example. Fora
// do CI, pula o teste se o Redis não estiver acessível — mantém
// `go test ./...` rodável sem docker compose no ar; no CI (P0.7) é
// obrigatório, então falha em vez de pular (mesmo critério de testPool nos
// outros serviços).
func testRedisURL(t *testing.T) string {
	t.Helper()
	if v := os.Getenv("REDIS_URL"); v != "" {
		return v
	}
	return "redis://localhost:6379/0"
}

func skipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// TestNewClientPingsRedis cobre o Aceite da P3.1: o pub/sub nasce configurado
// e a conexão é verificada na subida (main.go falha cedo se o Redis não
// responde).
func TestNewClientPingsRedis(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	client, err := pubsub.NewClient(ctx, testRedisURL(t))
	if err != nil {
		skipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = client.Close() })

	if err := client.Ping(ctx).Err(); err != nil {
		t.Fatalf("ping no Redis: %v", err)
	}
}

// TestPublishSubscribeRoundTrip confirma que uma mensagem publicada num canal
// chega ao assinante — o mecanismo base do fan-out de WS que a P3.2 vai usar
// entre conexões/instâncias.
func TestPublishSubscribeRoundTrip(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := pubsub.NewClient(ctx, testRedisURL(t))
	if err != nil {
		skipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = client.Close() })

	channel := "comms_test:" + t.Name()
	sub := client.Subscribe(ctx, channel)
	t.Cleanup(func() { _ = sub.Close() })

	// Confirma a inscrição antes de publicar — sem isso a mensagem pode ser
	// publicada antes do assinante estar pronto e se perder (pub/sub do Redis
	// não é fila persistente).
	if _, err := sub.Receive(ctx); err != nil {
		t.Fatalf("confirmar inscrição: %v", err)
	}

	if err := client.Publish(ctx, channel, "hello").Err(); err != nil {
		t.Fatalf("publicar: %v", err)
	}

	select {
	case msg := <-sub.Channel():
		if msg.Payload != "hello" {
			t.Fatalf("payload inesperado: %q", msg.Payload)
		}
	case <-ctx.Done():
		t.Fatal("timeout esperando a mensagem publicada")
	}
}
