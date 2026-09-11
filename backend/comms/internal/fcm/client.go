// Package fcm envia push via a FCM HTTP v1 API
// (POST https://fcm.googleapis.com/v1/projects/{project}/messages:send),
// autenticado por OAuth2 de conta de serviço.
//
// Escolha registrada na P3.4: `golang.org/x/oauth2/google` + chamada HTTP
// direta, em vez do Admin SDK oficial (`firebase.google.com/go/v4`). O SDK
// oficial cobriria a mesma necessidade (mandar 1 mensagem por token), mas
// arrasta uma árvore de dependências pensada para todo o produto Firebase
// (Firestore, Storage, Auth...); a chamada direta ao v1 é o que o SDK faz por
// baixo dos panos para Messaging.Send, então não perde nada essencial ao MVP
// e mantém o serviço com a mesma disciplina de dependência mínima do resto
// do backend (CLAUDE.md: "prefira o simples que passa no Aceite").
package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"

	"golang.org/x/oauth2/google"
)

// messagingScope é o único escopo necessário para mandar mensagens — o
// mínimo que a service account precisa (Console: Cloud Messaging API v1
// habilitada no projeto, ver backend/.env.example).
const messagingScope = "https://www.googleapis.com/auth/firebase.messaging"

// ErrUnregistered sinaliza que o FCM não reconhece mais o token (app
// desinstalado, token trocado do lado do Google) — quem chama Send pode
// reagir apagando o device_token correspondente (ver internal/push).
var ErrUnregistered = errors.New("fcm: token não registrado")

// Message é o conteúdo de um push — título/corpo já traduzidos (ADR-011 §3:
// o servidor renderiza no locale do destinatário) e dados extras para o app
// decidir o deep link ao tocar na notificação (P3.5).
type Message struct {
	Token string
	Title string
	Body  string
	Data  map[string]string
}

// Client envia mensagens via FCM HTTP v1.
type Client struct {
	httpClient *http.Client
	projectID  string
	endpoint   string
}

// newClient monta o Client com um http.Client e endpoint já resolvidos —
// separado de NewClient para os testes poderem injetar um httpClient/endpoint
// de teste sem depender de credencial nem rede do Google.
func newClient(httpClient *http.Client, projectID, endpoint string) *Client {
	return &Client{httpClient: httpClient, projectID: projectID, endpoint: endpoint}
}

// NewClient decodifica a credencial da service account (env
// FCM_CREDENTIALS_JSON — caminho de um arquivo .json ou o JSON inteiro
// inline, ver backend/comms/.env.example) e monta um client HTTP que renova
// o access token OAuth2 sozinho a cada chamada.
func NewClient(ctx context.Context, credentialsJSON string) (*Client, error) {
	raw, err := loadCredentials(credentialsJSON)
	if err != nil {
		return nil, err
	}

	var sa struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(raw, &sa); err != nil {
		return nil, fmt.Errorf("fcm: credencial inválida: %w", err)
	}
	if sa.ProjectID == "" {
		return nil, fmt.Errorf("fcm: credencial sem project_id")
	}

	cfg, err := google.JWTConfigFromJSON(raw, messagingScope)
	if err != nil {
		return nil, fmt.Errorf("fcm: montar config OAuth2: %w", err)
	}

	endpoint := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", sa.ProjectID)
	return newClient(cfg.Client(ctx), sa.ProjectID, endpoint), nil
}

// loadCredentials aceita as duas formas documentadas: JSON inline (começa com
// "{") ou caminho de arquivo .json.
func loadCredentials(v string) ([]byte, error) {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil, fmt.Errorf("fcm: FCM_CREDENTIALS_JSON vazia")
	}
	if strings.HasPrefix(v, "{") {
		return []byte(v), nil
	}
	data, err := os.ReadFile(v)
	if err != nil {
		return nil, fmt.Errorf("fcm: ler arquivo de credencial: %w", err)
	}
	return data, nil
}

// fcmErrorBody é o suficiente do corpo de erro da API v1 para distinguir
// token morto (UNREGISTERED/NOT_FOUND) do resto.
type fcmErrorBody struct {
	Error struct {
		Status string `json:"status"`
	} `json:"error"`
}

// Send manda uma mensagem para um token. Token morto vira ErrUnregistered;
// qualquer outro erro HTTP/rede vira um erro genérico envolvendo a causa.
func (c *Client) Send(ctx context.Context, msg Message) error {
	message := map[string]any{
		"token": msg.Token,
		"notification": map[string]string{
			"title": msg.Title,
			"body":  msg.Body,
		},
	}
	if len(msg.Data) > 0 {
		message["data"] = msg.Data
	}
	payload, err := json.Marshal(map[string]any{"message": message})
	if err != nil {
		return fmt.Errorf("fcm: serializar mensagem: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("fcm: montar requisição: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: enviar: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == http.StatusOK {
		return nil
	}

	var errBody fcmErrorBody
	_ = json.NewDecoder(resp.Body).Decode(&errBody)
	if resp.StatusCode == http.StatusNotFound || errBody.Error.Status == "UNREGISTERED" || errBody.Error.Status == "NOT_FOUND" {
		return ErrUnregistered
	}
	return fmt.Errorf("fcm: resposta %d (%s)", resp.StatusCode, errBody.Error.Status)
}
