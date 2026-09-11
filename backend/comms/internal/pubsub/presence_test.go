package pubsub_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
)

// TestPresenceMarkAndUnmark cobre o registro de presença entre instâncias que
// a P3.4 criou (Notas de execução da P3.2: internal/ws.Hub só sabe da própria
// instância, então a decisão de push de message.new precisa de outra fonte).
func TestPresenceMarkAndUnmark(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := pubsub.NewClient(ctx, testRedisURL(t))
	if err != nil {
		skipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = client.Close() })

	userID := uuid.NewString()
	connID := uuid.NewString()

	online, err := pubsub.IsOnline(ctx, client, userID)
	if err != nil {
		t.Fatalf("consultar presença antes de marcar: %v", err)
	}
	if online {
		t.Fatal("usuário novo não deveria estar online")
	}

	if err := pubsub.PresenceMark(ctx, client, userID, connID); err != nil {
		t.Fatalf("marcar presença: %v", err)
	}
	online, err = pubsub.IsOnline(ctx, client, userID)
	if err != nil {
		t.Fatalf("consultar presença depois de marcar: %v", err)
	}
	if !online {
		t.Fatal("usuário deveria estar online depois de PresenceMark")
	}

	if err := pubsub.PresenceUnmark(ctx, client, userID, connID); err != nil {
		t.Fatalf("desmarcar presença: %v", err)
	}
	online, err = pubsub.IsOnline(ctx, client, userID)
	if err != nil {
		t.Fatalf("consultar presença depois de desmarcar: %v", err)
	}
	if online {
		t.Fatal("usuário não deveria estar online depois de PresenceUnmark")
	}
}

// TestPresenceMultipleConnections cobre o caso de mais de uma conexão do
// mesmo usuário (dois devices abertos): sair de uma não derruba a presença
// da outra.
func TestPresenceMultipleConnections(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := pubsub.NewClient(ctx, testRedisURL(t))
	if err != nil {
		skipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = client.Close() })

	userID := uuid.NewString()
	connA, connB := uuid.NewString(), uuid.NewString()

	if err := pubsub.PresenceMark(ctx, client, userID, connA); err != nil {
		t.Fatalf("marcar conexão A: %v", err)
	}
	if err := pubsub.PresenceMark(ctx, client, userID, connB); err != nil {
		t.Fatalf("marcar conexão B: %v", err)
	}
	if err := pubsub.PresenceUnmark(ctx, client, userID, connA); err != nil {
		t.Fatalf("desmarcar conexão A: %v", err)
	}

	online, err := pubsub.IsOnline(ctx, client, userID)
	if err != nil {
		t.Fatalf("consultar presença: %v", err)
	}
	if !online {
		t.Fatal("usuário deveria continuar online com a conexão B ainda ativa")
	}
}
