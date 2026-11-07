package obs_test

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"

	"github.com/marcus-coube/lyfta/workout/internal/obs"
)

type fakeTransport struct{ events []*sentry.Event }

func (f *fakeTransport) Flush(time.Duration) bool              { return true }
func (f *fakeTransport) FlushWithContext(context.Context) bool { return true }
func (f *fakeTransport) Configure(sentry.ClientOptions)        {}
func (f *fakeTransport) SendEvent(e *sentry.Event)             { f.events = append(f.events, e) }
func (f *fakeTransport) Close()                                {}

func TestInitSemDSNNaoLigaNada(t *testing.T) {
	flush, err := obs.Init("svc", "", "test", "")
	if err != nil {
		t.Fatalf("Init com DSN vazio deve ser no-op, veio %v", err)
	}
	flush()
	// O SDK já tem um cliente padrão sem DSN (transporte nulo, descarta tudo);
	// o que importa é Init não ter configurado nenhum DSN.
	if c := sentry.CurrentHub().Client(); c != nil && c.Options().Dsn != "" {
		t.Fatal("DSN vazio não pode deixar DSN configurado")
	}
}

// O filtro de evento (ADR-008) tira e-mail, nome, IP, corpo, headers, cookies
// e query string; só user_id e a rota sem query sobrevivem.
func TestScrubEventRemovePII(t *testing.T) {
	tr := &fakeTransport{}
	client, err := sentry.NewClient(sentry.ClientOptions{
		Dsn:              "https://public@example.invalid/1",
		Transport:        tr,
		BeforeSend:       obs.ScrubEvent,
		BeforeBreadcrumb: obs.ScrubBreadcrumb,
	})
	if err != nil {
		t.Fatal(err)
	}
	scope := sentry.NewScope()
	scope.SetUser(sentry.User{ID: "u1", Email: "a@b.com", Username: "Ana", IPAddress: "1.2.3.4", Name: "Ana Silva"})
	scope.SetTag("tenant_id", "t1")
	req := httptest.NewRequest("POST", "https://x.test/v1/me?email=a@b.com&secret=1", strings.NewReader(`{"email":"a@b.com"}`))
	req.Header.Set("Authorization", "Bearer abc")
	scope.SetRequest(req)
	scope.AddBreadcrumb(&sentry.Breadcrumb{
		Category: "http",
		Data: map[string]interface{}{
			"url":     "https://x.test/v1/me?email=a@b.com",
			"headers": "Authorization: Bearer abc",
			"query":   "email=a@b.com",
			"status":  200,
		},
	}, 10)
	client.CaptureMessage("boom", nil, scope)

	if len(tr.events) != 1 {
		t.Fatalf("esperava 1 evento, veio %d", len(tr.events))
	}
	e := tr.events[0]
	if e.User.ID != "u1" || e.User.Email != "" || e.User.Username != "" || e.User.IPAddress != "" || e.User.Name != "" {
		t.Errorf("user deve ter só ID: %+v", e.User)
	}
	if e.Tags["tenant_id"] != "t1" {
		t.Errorf("tenant_id deve ficar: %v", e.Tags)
	}
	r := e.Request
	if r == nil {
		t.Fatal("request ausente")
	}
	if r.Data != "" || r.QueryString != "" || r.Cookies != "" || len(r.Headers) != 0 || len(r.Env) != 0 {
		t.Errorf("request deve ficar sem corpo/query/headers/cookies: %+v", r)
	}
	if r != nil && (strings.Contains(r.URL, "?") || strings.Contains(r.URL, "secret")) {
		t.Errorf("URL com query vazou: %q", r.URL)
	}
	if len(e.Breadcrumbs) != 1 {
		t.Fatalf("breadcrumbs: %d", len(e.Breadcrumbs))
	}
	d := e.Breadcrumbs[0].Data
	if _, ok := d["headers"]; ok {
		t.Error("headers do breadcrumb vazaram")
	}
	if _, ok := d["query"]; ok {
		t.Error("query do breadcrumb vazou")
	}
	if u, _ := d["url"].(string); strings.Contains(u, "?") {
		t.Errorf("url do breadcrumb com query: %q", u)
	}
	if d["status"] != 200 {
		t.Error("campos inofensivos devem ficar")
	}
}

// ScrubEvent direto, sem depender do que o SDK já filtra por padrão.
func TestScrubEventRequestCompleto(t *testing.T) {
	r := httpReq
	e := obs.ScrubEvent(&sentry.Event{
		User:    sentry.User{ID: "u1", Email: "a@b.com"},
		Request: &r,
	}, nil)
	if e.User.Email != "" || e.User.ID != "u1" {
		t.Errorf("user: %+v", e.User)
	}
	got := e.Request
	if got.Data != "" || got.QueryString != "" || got.Cookies != "" || len(got.Headers) != 0 || len(got.Env) != 0 {
		t.Errorf("request não foi limpo: %+v", got)
	}
	if got.URL != "https://x.test/v1/me" || got.Method != "POST" {
		t.Errorf("URL/método: %q %q", got.URL, got.Method)
	}
}

var httpReq = sentry.Request{
	URL:         "https://x.test/v1/me?email=a@b.com&secret=1",
	Method:      "POST",
	Data:        `{"email":"a@b.com"}`,
	QueryString: "email=a@b.com&secret=1",
	Cookies:     "session=abc",
	Headers:     map[string]string{"Authorization": "Bearer abc"},
	Env:         map[string]string{"REMOTE_ADDR": "1.2.3.4"},
}
