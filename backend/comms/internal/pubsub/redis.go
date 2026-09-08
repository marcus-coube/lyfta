// Package pubsub encapsula o client Redis do comms — o canal de fan-out de
// eventos do WebSocket entre instâncias (P3.2: message.new, message.read).
//
// Mesmo com uma única instância do serviço hoje, o pub/sub já nasce
// configurado: publicar/assinar por aqui deixa a topologia (1 instância ou N
// atrás de load balancer) como detalhe de infra, não de código.
package pubsub

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
)

// NewClient cria o client Redis a partir da REDIS_URL (backend/README.md) e
// confirma a conexão com PING — falhar cedo aqui é melhor que descobrir só na
// primeira publicação de mensagem (P3.2).
func NewClient(ctx context.Context, redisURL string) (*redis.Client, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("pubsub: REDIS_URL inválida: %w", err)
	}

	client := redis.NewClient(opts)
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("pubsub: ping no Redis: %w", err)
	}
	return client, nil
}
