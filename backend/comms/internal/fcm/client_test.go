package fcm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Testes de unidade puros (sem rede/credencial do Google): newClient injeta
// um httpClient/endpoint apontando pro httptest.Server, exercitando só o
// contrato HTTP do Send (corpo da mensagem, status de sucesso, mapeamento de
// token morto para ErrUnregistered).

func TestSendHappyPath(t *testing.T) {
	var gotBody map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decodificar corpo enviado: %v", err)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"name":"projects/p/messages/1"}`))
	}))
	defer server.Close()

	client := newClient(server.Client(), "p", server.URL)
	err := client.Send(context.Background(), Message{
		Token: "tok-1", Title: "Título", Body: "Corpo", Data: map[string]string{"type": "message.new"},
	})
	if err != nil {
		t.Fatalf("Send: %v", err)
	}

	msg, ok := gotBody["message"].(map[string]any)
	if !ok {
		t.Fatalf("corpo enviado sem `message`: %+v", gotBody)
	}
	if msg["token"] != "tok-1" {
		t.Fatalf("token errado no corpo: %+v", msg)
	}
	notification, _ := msg["notification"].(map[string]any)
	if notification["title"] != "Título" || notification["body"] != "Corpo" {
		t.Fatalf("notification errada no corpo: %+v", notification)
	}
	data, _ := msg["data"].(map[string]any)
	if data["type"] != "message.new" {
		t.Fatalf("data errada no corpo: %+v", data)
	}
}

func TestSendUnregisteredToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"error":{"status":"UNREGISTERED"}}`))
	}))
	defer server.Close()

	client := newClient(server.Client(), "p", server.URL)
	err := client.Send(context.Background(), Message{Token: "tok-morto", Title: "t", Body: "b"})
	if err != ErrUnregistered {
		t.Fatalf("esperava ErrUnregistered, veio %v", err)
	}
}

func TestSendGenericServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":{"status":"INTERNAL"}}`))
	}))
	defer server.Close()

	client := newClient(server.Client(), "p", server.URL)
	err := client.Send(context.Background(), Message{Token: "tok", Title: "t", Body: "b"})
	if err == nil || err == ErrUnregistered {
		t.Fatalf("esperava erro genérico, veio %v", err)
	}
}

func TestNewClientRejectsEmptyCredentials(t *testing.T) {
	if _, err := NewClient(context.Background(), ""); err == nil {
		t.Fatal("FCM_CREDENTIALS_JSON vazia deveria falhar")
	}
}

func TestNewClientRejectsInvalidJSON(t *testing.T) {
	if _, err := NewClient(context.Background(), "{não é json"); err == nil {
		t.Fatal("JSON inline inválido deveria falhar")
	}
}
