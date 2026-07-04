package mail

import (
	"context"
	"log/slog"
)

// logMailer loga o e-mail no stdout (via slog) em vez de enviar de verdade —
// usado em dev sem RESEND_API_KEY e nos testes de handler, para o fluxo
// completo (convite/reset) ser exercitável sem chave real (Aceite do P0.4).
type logMailer struct {
	logger *slog.Logger
}

// NewLogMailer cria um Mailer que apenas loga o conteúdo do e-mail.
func NewLogMailer(logger *slog.Logger) Mailer {
	return &logMailer{logger: logger}
}

func (m *logMailer) Send(_ context.Context, msg Message) error {
	m.logger.Info("mail_send_logged",
		slog.String("to", msg.To),
		slog.String("subject", msg.Subject),
		slog.String("html", msg.HTML),
	)
	return nil
}
