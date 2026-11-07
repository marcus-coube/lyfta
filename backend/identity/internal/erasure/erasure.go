// Package erasure orquestra a exclusão dos dados de um usuário nos outros
// serviços (ADR-008 §2, P4.5). Só HTTP com X-Internal-Token (ADR-013 §5):
// nenhum import de código nem acesso ao banco de outro serviço.
package erasure

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Target é um serviço que guarda dados do usuário.
type Target struct {
	Name    string
	BaseURL string
}

// Client chama DELETE /internal/v1/users/{id} em cada Target.
type Client struct {
	targets []Target
	token   string
	http    *http.Client
}

// New cria o cliente de exclusão.
func New(token string, targets []Target) *Client {
	return &Client{targets: targets, token: token, http: &http.Client{Timeout: 20 * time.Second}}
}

// Erase pede a exclusão em todos os serviços. Não para no primeiro erro —
// cada serviço é idempotente, então tentar todos deixa a repetição da chamada
// só com o que faltou. Devolve os nomes dos serviços que falharam.
func (c *Client) Erase(ctx context.Context, tenantID, userID string) (failed []string) {
	for _, t := range c.targets {
		if err := c.eraseOne(ctx, t, tenantID, userID); err != nil {
			failed = append(failed, t.Name)
		}
	}
	return failed
}

func (c *Client) eraseOne(ctx context.Context, t Target, tenantID, userID string) error {
	target := fmt.Sprintf("%s/internal/v1/users/%s?tenant_id=%s",
		strings.TrimSuffix(t.BaseURL, "/"), url.PathEscape(userID), url.QueryEscape(tenantID))
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, target, nil)
	if err != nil {
		return err
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
