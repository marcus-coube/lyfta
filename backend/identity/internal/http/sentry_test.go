package http_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
	"github.com/go-chi/chi/v5"

	whttp "github.com/marcus-coube/lyfta/identity/internal/http"
)

type captureTransport struct{ events []*sentry.Event }

func (c *captureTransport) Flush(time.Duration) bool              { return true }
func (c *captureTransport) FlushWithContext(context.Context) bool { return true }
func (c *captureTransport) Configure(sentry.ClientOptions)        {}
func (c *captureTransport) SendEvent(e *sentry.Event)             { c.events = append(c.events, e) }
func (c *captureTransport) Close()                                {}

func newErrRouter() http.Handler {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	r := chi.NewRouter()
	r.Use(whttp.RequestID)
	r.Use(whttp.SentryScope)
	r.Use(whttp.Recover(logger))
	r.Use(whttp.ReportServerErrors)
	r.Get("/boom", func(http.ResponseWriter, *http.Request) { panic("kaboom") })
	r.Get("/fail/{id}", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusInternalServerError) })
	r.Get("/bad", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusBadRequest) })
	r.Get("/ok", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	return r
}

func serve(h http.Handler, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("X-Request-Id", "req-123")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// Sem cliente Sentry ligado (DSN vazio), panic ainda vira 500 JSON e o
// processo segue de pé.
func TestRecoverPanicVira500SemSentry(t *testing.T) {
	h := newErrRouter()
	rec := serve(h, "/boom")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, quer 500", rec.Code)
	}
	if got := rec.Body.String(); got != `{"code":"internal_error","params":{}}` {
		t.Fatalf("corpo = %s", got)
	}
	if rec2 := serve(h, "/ok"); rec2.Code != http.StatusOK {
		t.Fatalf("o handler seguinte deve responder normalmente: %d", rec2.Code)
	}
	if rec3 := serve(h, "/fail/9"); rec3.Code != http.StatusInternalServerError {
		t.Fatalf("5xx sem Sentry segue 500: %d", rec3.Code)
	}
}

func TestPanicE5xxSaoReportadosComRequestID(t *testing.T) {
	tr := &captureTransport{}
	client, err := sentry.NewClient(sentry.ClientOptions{Dsn: "https://public@example.invalid/1", Transport: tr})
	if err != nil {
		t.Fatal(err)
	}
	// SentryScope clona o hub corrente: liga o cliente de teste nele e
	// desliga ao fim.
	sentry.CurrentHub().BindClient(client)
	t.Cleanup(func() { sentry.CurrentHub().BindClient(nil) })

	h := newErrRouter()

	if rec := serve(h, "/boom"); rec.Code != http.StatusInternalServerError {
		t.Fatalf("panic: status %d", rec.Code)
	}
	if len(tr.events) != 1 {
		t.Fatalf("panic deve gerar exatamente 1 evento, veio %d", len(tr.events))
	}
	if tr.events[0].Tags["request_id"] != "req-123" {
		t.Errorf("request_id ausente: %v", tr.events[0].Tags)
	}

	serve(h, "/fail/9")
	if len(tr.events) != 2 {
		t.Fatalf("500 deve gerar 1 evento a mais, total %d", len(tr.events))
	}
	if tr.events[1].Tags["request_id"] != "req-123" {
		t.Errorf("request_id ausente no 5xx: %v", tr.events[1].Tags)
	}
	if got := tr.events[1].Message; got != "http Internal Server Error: GET /fail/{id}" {
		t.Errorf("mensagem deve usar o padrão da rota, não o path real: %q", got)
	}

	serve(h, "/bad")
	serve(h, "/ok")
	if len(tr.events) != 2 {
		t.Fatalf("4xx e 2xx não são reportados, total %d", len(tr.events))
	}
}
