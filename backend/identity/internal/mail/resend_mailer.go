package mail

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// resendAPIURL é o endpoint de envio da API do Resend (backend/README.md:
// Resend é o provedor de e-mail transacional pinado do identity).
const resendAPIURL = "https://api.resend.com/emails"

// resendMailer envia e-mail via API HTTP do Resend, sem SDK (net/http puro —
// evita adicionar dependência nova só para chamar um endpoint REST simples).
type resendMailer struct {
	apiKey   string
	from     string
	client   *http.Client
	endpoint string
}

// NewResendMailer cria um Mailer que envia via API do Resend. apiKey e from
// vêm de env (RESEND_API_KEY, MAIL_FROM — backend/identity/.env.example).
func NewResendMailer(apiKey, from string) Mailer {
	return &resendMailer{
		apiKey:   apiKey,
		from:     from,
		client:   &http.Client{Timeout: 10 * time.Second},
		endpoint: resendAPIURL,
	}
}

type resendRequest struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	HTML    string   `json:"html"`
}

func (m *resendMailer) Send(ctx context.Context, msg Message) error {
	body, err := json.Marshal(resendRequest{
		From:    m.from,
		To:      []string{msg.To},
		Subject: msg.Subject,
		HTML:    msg.HTML,
	})
	if err != nil {
		return fmt.Errorf("mail: montar payload do Resend: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("mail: montar requisição do Resend: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+m.apiKey)

	resp, err := m.client.Do(req)
	if err != nil {
		return fmt.Errorf("mail: chamar API do Resend: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("mail: Resend respondeu status %d", resp.StatusCode)
	}
	return nil
}
