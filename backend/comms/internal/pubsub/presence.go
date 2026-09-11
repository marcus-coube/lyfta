package pubsub

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// presenceKeyPrefix identifica o conjunto Redis de conexões WS ativas de um
// usuário — compartilhado entre todas as instâncias do comms (ao contrário
// do internal/ws.Hub, que só sabe das conexões presas ao próprio processo).
// A P3.4 consulta isso para decidir se manda push de message.new: destinatário
// com alguma conexão ativa em QUALQUER instância não recebe push, porque já
// está vendo o evento chegar pelo WS.
const presenceKeyPrefix = "comms:presence:"

// presenceTTL cobre o caso de a instância cair sem chamar PresenceUnmark
// (crash, kill -9): sem isso, uma marca órfã deixaria o usuário "online"
// para sempre e ele nunca mais receberia push de mensagem nova. Renovada a
// cada ping do WS (ver ws.go) — bem maior que o intervalo de ping
// (wsPingInterval, 30s) para não expirar por uma renovação atrasada.
const presenceTTL = 90 * time.Second

func presenceKey(userID string) string { return presenceKeyPrefix + userID }

// PresenceMark anuncia que a conexão connID do usuário está ativa nesta
// instância — chamado no registro da conexão WS e renovado a cada ping
// (WritePing bem-sucedido).
func PresenceMark(ctx context.Context, client *redis.Client, userID, connID string) error {
	key := presenceKey(userID)
	pipe := client.TxPipeline()
	pipe.SAdd(ctx, key, connID)
	pipe.Expire(ctx, key, presenceTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("pubsub: marcar presença: %w", err)
	}
	return nil
}

// PresenceUnmark remove a marca de uma conexão que fechou (defer no handler
// de WS, mesmo padrão do Hub.Unregister).
func PresenceUnmark(ctx context.Context, client *redis.Client, userID, connID string) error {
	if err := client.SRem(ctx, presenceKey(userID), connID).Err(); err != nil {
		return fmt.Errorf("pubsub: desmarcar presença: %w", err)
	}
	return nil
}

// IsOnline diz se o usuário tem alguma conexão ativa em qualquer instância —
// é o que a P3.4 consulta antes de mandar push de message.new.
func IsOnline(ctx context.Context, client *redis.Client, userID string) (bool, error) {
	n, err := client.SCard(ctx, presenceKey(userID)).Result()
	if err != nil {
		return false, fmt.Errorf("pubsub: consultar presença: %w", err)
	}
	return n > 0, nil
}
