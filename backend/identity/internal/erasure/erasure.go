// Package erasure orquestra a exclusão dos dados de um usuário nos outros
// serviços (ADR-008 §2, P4.5). Só HTTP com X-Internal-Token (ADR-013 §5):
// nenhum import de código nem acesso ao banco de outro serviço.
package erasure

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Target é um serviço que guarda dados do usuário.
type Target struct {
	Name    string
	BaseURL string
	// Profile: o serviço recebe nome e e-mail do usuário no corpo do DELETE.
	// Só o billing, que retém o titular no financeiro (ADR-017 §5); os outros
	// não precisam do dado pessoal e não o recebem.
	Profile bool
}

// Profile é o dado do titular que o billing guarda após a exclusão.
type Profile struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Pending é a resposta do billing sobre faturas em aberto (ADR-017 §5).
type Pending struct {
	Pending         bool `json:"pending"`
	OpenInvoices    int  `json:"open_invoices"`
	OverdueInvoices int  `json:"overdue_invoices"`
}

// Client chama DELETE /internal/v1/users/{id} em cada Target.
type Client struct {
	targets []Target
	token   string
	http    *http.Client
	// billingURL: base do billing para a consulta de pendência ("" = sem
	// financeiro, nunca há pendência).
	billingURL string
}

// WithBilling habilita a consulta de faturas pendentes no billing.
func (c *Client) WithBilling(baseURL string) *Client {
	c.billingURL = baseURL
	return c
}

// Pending pergunta ao billing se o usuário tem fatura `open` ou `overdue`.
// Qualquer falha de comunicação vira erro: quem chama não segue adiante.
func (c *Client) Pending(ctx context.Context, tenantID, userID string) (Pending, error) {
	if c.billingURL == "" {
		return Pending{}, nil
	}
	target := fmt.Sprintf("%s/internal/v1/users/%s/pending?tenant_id=%s",
		strings.TrimSuffix(c.billingURL, "/"), url.PathEscape(userID), url.QueryEscape(tenantID))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return Pending{}, err
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return Pending{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Pending{}, fmt.Errorf("erasure: billing respondeu %d", resp.StatusCode)
	}
	var out Pending
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return Pending{}, fmt.Errorf("erasure: resposta do billing: %w", err)
	}
	return out, nil
}

// New cria o cliente de exclusão.
func New(token string, targets []Target) *Client {
	return &Client{targets: targets, token: token, http: &http.Client{Timeout: 20 * time.Second}}
}

// Erase pede a exclusão em todos os serviços. Não para no primeiro erro —
// cada serviço é idempotente, então tentar todos deixa a repetição da chamada
// só com o que faltou. Devolve os nomes dos serviços que falharam.
func (c *Client) Erase(ctx context.Context, tenantID, userID string, profile Profile) (failed []string) {
	for _, t := range c.targets {
		if err := c.eraseOne(ctx, t, tenantID, userID, profile); err != nil {
			failed = append(failed, t.Name)
		}
	}
	return failed
}

func (c *Client) eraseOne(ctx context.Context, t Target, tenantID, userID string, profile Profile) error {
	target := fmt.Sprintf("%s/internal/v1/users/%s?tenant_id=%s",
		strings.TrimSuffix(t.BaseURL, "/"), url.PathEscape(userID), url.QueryEscape(tenantID))
	var body io.Reader
	if t.Profile {
		raw, err := json.Marshal(profile)
		if err != nil {
			return err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, target, body)
	if err != nil {
		return err
	}
	if t.Profile {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("erasure: %s respondeu %d", t.Name, resp.StatusCode)
	}
	return nil
}
