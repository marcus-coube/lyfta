// Package obs liga o relato de erros ao Sentry/GlitchTip (ADR-009 §5, P4.6).
//
// Duplicado em cada serviço de propósito (ADR-013: nenhum pacote
// compartilhado). DSN vazio = desligado: nada é inicializado e nenhum evento
// sai do processo. Privacidade (ADR-008): o evento leva só user_id/tenant_id —
// ScrubEvent remove corpo, query, headers, cookies, e-mail, nome e IP.
package obs

import (
	"net/url"
	"time"

	"github.com/getsentry/sentry-go"
)

// Init liga o Sentry e devolve o flush a chamar no shutdown. Com DSN vazio
// não faz nada (flush é no-op) e o serviço se comporta como antes.
func Init(service, dsn, environment, release string) (func(), error) {
	if dsn == "" {
		return func() {}, nil
	}
	err := sentry.Init(sentry.ClientOptions{
		Dsn:              dsn,
		Environment:      environment,
		Release:          release,
		ServerName:       service,
		SendDefaultPII:   false,
		AttachStacktrace: true,
		BeforeSend:       ScrubEvent,
		BeforeBreadcrumb: ScrubBreadcrumb,
	})
	if err != nil {
		return func() {}, err
	}
	sentry.ConfigureScope(func(s *sentry.Scope) { s.SetTag("service", service) })
	return func() { sentry.Flush(2 * time.Second) }, nil
}

// ScrubEvent é o filtro de PII (ADR-008): mantém só o id do usuário e a rota
// sem query. Tags (tenant_id, request_id, service) ficam.
func ScrubEvent(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
	event.User = sentry.User{ID: event.User.ID}
	if event.Request != nil {
		event.Request = &sentry.Request{
			URL:    stripQuery(event.Request.URL),
			Method: event.Request.Method,
		}
	}
	for _, b := range event.Breadcrumbs {
		scrubBreadcrumbData(b)
	}
	return event
}

// ScrubBreadcrumb tira query string e headers dos breadcrumbs.
func ScrubBreadcrumb(b *sentry.Breadcrumb, _ *sentry.BreadcrumbHint) *sentry.Breadcrumb {
	scrubBreadcrumbData(b)
	return b
}

func scrubBreadcrumbData(b *sentry.Breadcrumb) {
	if b == nil || b.Data == nil {
		return
	}
	for _, k := range []string{"headers", "query", "query_string", "body", "http.query", "http.fragment", "http.request.headers"} {
		delete(b.Data, k)
	}
	if u, ok := b.Data["url"].(string); ok {
		b.Data["url"] = stripQuery(u)
	}
}

func stripQuery(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	u.RawQuery, u.Fragment, u.User = "", "", nil
	return u.String()
}
