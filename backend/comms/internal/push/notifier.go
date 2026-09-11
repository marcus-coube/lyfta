// Package push monta e manda as notificações do MVP (P3.4, ADR-012): nova
// mensagem para quem não está com o WS aberto, check-in de dor forte para o
// coach, e o job diário de treino pendente (internal/job). O texto é
// renderizado aqui — no servidor, no locale do destinatário (ADR-011 §3) —,
// nunca no locale de quem disparou o evento: quem chama Send é sempre o
// remetente/aluno da ação (a claim disponível no request é a dele, não a de
// quem vai receber o push), então o locale sai de device_tokens.locale
// (gravado por POST /v1/devices), a única fonte disponível fora de uma
// requisição HTTP do próprio destinatário — ver Notas de execução da P3.4.
package push

import (
	"context"
	"errors"
	"log/slog"

	"github.com/marcus-coube/lyfta/comms/internal/fcm"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// Kind identifica o tipo de notificação — vira o `kind` gravado em
// notification_log e a chave de tradução (ver messages.go).
type Kind string

const (
	KindMessageNew        Kind = "message_new"
	KindCheckinPainStrong Kind = "checkin_pain_strong"
	KindWorkoutPending    Kind = "workout_pending"
)

// Pusher é o transporte de push — satisfeito por *fcm.Client em produção e
// por um fake nos testes (não faz sentido bater na Google/precisar de
// credencial só para testar o resto do pipeline: device lookup, render,
// log).
type Pusher interface {
	Send(ctx context.Context, msg fcm.Message) error
}

// Notifier junta as três peças do push: de onde tirar o(s) token(s) do
// destinatário, como mandar, e onde registrar o envio.
type Notifier struct {
	logger        *slog.Logger
	deviceTokens  *repo.DeviceTokenRepo
	notifications *repo.NotificationLogRepo
	pusher        Pusher
}

// NewNotifier cria um Notifier. pusher pode ser nil — quando
// FCM_CREDENTIALS_JSON não está configurada (dev sem Firebase), Send apenas
// loga e não faz nada, em vez de o serviço inteiro recusar subir por causa de
// uma feature que não bloqueia chat nem check-in.
func NewNotifier(logger *slog.Logger, deviceTokens *repo.DeviceTokenRepo, notifications *repo.NotificationLogRepo, pusher Pusher) *Notifier {
	return &Notifier{logger: logger, deviceTokens: deviceTokens, notifications: notifications, pusher: pusher}
}

// Send manda o push para todos os devices registrados do usuário (mais de um
// quando ele tem o app aberto em mais de uma plataforma), cada um no próprio
// locale, e grava um notification_log por envio bem-sucedido — a auditoria
// ("chegou mesmo?") pede um registro por push de verdade, não um resumo por
// usuário; só o dedupe do job diário (internal/job) precisa perguntar "já
// mandei hoje", e essa pergunta (ExistsInRange) não se importa com quantas
// linhas existem, só se existe alguma.
//
// Erro ao listar devices ou ao mandar um push específico é logado e não
// propagado: falha de push não pode derrubar o fluxo de negócio que a
// disparou (mensagem/check-in já estão gravados quando Send é chamado).
func (n *Notifier) Send(ctx context.Context, tenantID, userID string, kind Kind, data map[string]string) {
	if n.pusher == nil {
		n.logger.Debug("push_disabled", slog.String("kind", string(kind)))
		return
	}

	tokens, err := n.deviceTokens.ListForUser(ctx, tenantID, userID)
	if err != nil {
		n.logger.Error("push_list_devices_failed", slog.Any("error", err))
		return
	}

	for _, dt := range tokens {
		title, body := renderText(kind, dt.Locale)
		sendErr := n.pusher.Send(ctx, fcm.Message{Token: dt.Token, Title: title, Body: body, Data: data})
		if sendErr != nil {
			if errors.Is(sendErr, fcm.ErrUnregistered) {
				if delErr := n.deviceTokens.Delete(ctx, tenantID, userID, dt.Token); delErr != nil {
					n.logger.Error("push_delete_stale_token_failed", slog.Any("error", delErr))
				}
			}
			n.logger.Error("push_send_failed", slog.Any("error", sendErr),
				slog.String("user_id", userID), slog.String("kind", string(kind)))
			continue
		}
		if logErr := n.notifications.Record(ctx, tenantID, userID, string(kind), map[string]any{"title": title, "body": body}); logErr != nil {
			n.logger.Error("push_log_failed", slog.Any("error", logErr))
		}
	}
}
