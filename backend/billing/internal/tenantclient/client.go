// Package tenantclient lista os tenants (id + fuso IANA) no identity por M2M
// (ADR-013 §4/§5, P5.1) para o job mensal do financeiro rodar no fuso de cada
// tenant. A lista inteira fica em cache em memória por TTL (10 min por
// padrão): tenant novo ou fuso alterado vale na instância em até esse prazo.
package tenantclient

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// DefaultTTL é o prazo do cache da lista de tenants.
const DefaultTTL = 10 * time.Minute

// Tenant é um item de GET /internal/v1/tenants.
type Tenant struct {
	ID       string `json:"id"`
	Timezone string `json:"timezone"`
}

// Client consulta o identity.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
	ttl     time.Duration
	now     func() time.Time

	mu        sync.Mutex
	cached    []Tenant
	expiresAt time.Time
}

// NewClient cria o cliente. ttl <= 0 desliga o cache.
func NewClient(baseURL, token string, ttl time.Duration) *Client {
	return &Client{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		token:   token,
		http:    &http.Client{Timeout: 10 * time.Second},
		ttl:     ttl,
		now:     time.Now,
	}
}

// List devolve todos os tenants, percorrendo as páginas por cursor. Falha do
// identity vira erro e não é cacheada.
func (c *Client) List(ctx context.Context) ([]Tenant, error) {
	if c.ttl > 0 {
		c.mu.Lock()
		cached, expires := c.cached, c.expiresAt
		c.mu.Unlock()
		if cached != nil && c.now().Before(expires) {
			return cached, nil
		}
	}

	var all []Tenant
	after := ""
	for {
		q := url.Values{}
		q.Set("limit", "500")
		if after != "" {
			q.Set("after", after)
		}
		var body struct {
			Items      []Tenant `json:"items"`
			NextCursor string   `json:"next_cursor"`
		}
		if err := c.get(ctx, c.baseURL+"/internal/v1/tenants?"+q.Encode(), &body); err != nil {
			return nil, err
		}
		all = append(all, body.Items...)
		if body.NextCursor == "" {
			break
		}
		after = body.NextCursor
	}

	if c.ttl > 0 {
		c.mu.Lock()
		c.cached, c.expiresAt = all, c.now().Add(c.ttl)
		c.mu.Unlock()
	}
	return all, nil
}

func (c *Client) get(ctx context.Context, target string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return fmt.Errorf("tenantclient: montar requisição: %w", err)
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("tenantclient: chamar identity: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("tenantclient: identity respondeu %d", resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("tenantclient: decodificar resposta: %w", err)
	}
	return nil
}
