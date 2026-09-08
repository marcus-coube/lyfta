package pubsub

import (
	"context"
	"log/slog"
	"strings"

	"github.com/redis/go-redis/v9"
)

// userChannelPrefix identifica o canal Redis de um usuário — o fan-out de
// eventos de WS (message.new, message.read) publica aqui, e cada instância
// do comms assina o padrão inteiro (Relay) para entregar às conexões que
// tem localmente (internal/ws.Hub). Publicar por usuário, não por conversa,
// mantém o mecanismo simples: quem recebe o evento é sempre um participante
// (o handler HTTP publica só para student_id e coach_id da conversa), e a
// P3.4 reusa o mesmo canal para saber se o destinatário está com o app
// aberto antes de mandar push.
const userChannelPrefix = "comms:user:"

func userChannel(userID string) string { return userChannelPrefix + userID }

// PublishToUser publica um evento (já serializado) no canal do usuário.
func PublishToUser(ctx context.Context, client *redis.Client, userID string, payload []byte) error {
	return client.Publish(ctx, userChannel(userID), payload).Err()
}

// Relay assina `comms:user:*` e entrega cada mensagem recebida ao callback
// informado (userID extraído do canal, payload cru). Roda até o contexto ser
// cancelado — chamado como goroutine de longa duração a partir do main.go,
// uma por instância do serviço. logger fica disponível para diagnósticos
// futuros (hoje deliver não devolve erro para logar).
func Relay(ctx context.Context, client *redis.Client, logger *slog.Logger, deliver func(userID string, payload []byte)) {
	sub := client.PSubscribe(ctx, userChannelPrefix+"*")
	defer func() { _ = sub.Close() }()

	ch := sub.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			userID := strings.TrimPrefix(msg.Channel, userChannelPrefix)
			if userID == "" {
				continue
			}
			deliver(userID, []byte(msg.Payload))
		}
	}
}
