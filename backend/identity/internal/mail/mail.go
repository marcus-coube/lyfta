// Package mail envia e-mails transacionais do serviço identity (convites e
// recuperação de senha — P0.4). Provedor: Resend (backend/README.md).
package mail

import "context"

// Message é o e-mail a ser enviado — HTML inline simples, pt-BR (não é
// conteúdo de UI sujeito a i18n de cliente, ADR-011 trata isso como texto de
// servidor, igual aos códigos de erro).
type Message struct {
	To      string
	Subject string
	HTML    string
}

// Mailer abstrai o envio de e-mail para permitir logMailer em dev/teste (sem
// depender de RESEND_API_KEY real) e resendMailer em produção.
type Mailer interface {
	Send(ctx context.Context, msg Message) error
}
