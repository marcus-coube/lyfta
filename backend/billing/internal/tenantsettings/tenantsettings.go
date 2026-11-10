// Package tenantsettings lê no identity, por M2M (ADR-013 §4/§5), as
// configurações do tenant que o billing precisa: fuso IANA (ADR-007 §3) e o
// modo de acesso do coach ao financeiro (ADR-017 §3). A resposta fica em
// cache em memória por tenant durante o TTL — a troca do modo vale nesta
// instância em até o TTL (30 s). Falha do identity vira erro, nunca cacheada:
// quem chama fecha o acesso (mesma regra do coachlink).
package tenantsettings

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// DefaultTTL é o prazo do cache quando TENANT_SETTINGS_CACHE_TTL não é
// informado.
const DefaultTTL = 30 * time.Second

// Modos de acesso do coach ao financeiro (ADR-017 §3).
const (
	AccessStatusOnly  = "status_only"
	AccessOwnStudents = "own_students"
)

// ErrTenantNotFound: o identity não conhece o tenant.
var ErrTenantNotFound = errors.New("tenantsettings: tenant não encontrado")

// Settings são as configurações do tenant relevantes ao billing.
type Settings struct {
	ID                 string `json:"id"`
	Timezone           string `json:"timezone"`
	CoachBillingAccess string `json:"coach_billing_access"`
}

// Location devolve o fuso do tenant; fuso inválido cai em America/Sao_Paulo
// (default do ADR-007 §3).
func (s Settings) Location() *time.Location {
	if loc, err := time.LoadLocation(s.Timezone); err == nil {
		return loc
	}
	loc, err := time.LoadLocation("America/Sao_Paulo")
	if err != nil {
		return time.UTC
	}
	return loc
}

type entry struct {
	settings  Settings
	expiresAt time.Time
}

// Client consulta o identity.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
	ttl     time.Duration
	now     func() time.Time

	mu    sync.Mutex
	cache map[string]entry
}

// NewClient cria o cliente. ttl <= 0 desliga o cache.
func NewClient(baseURL, token string, ttl time.Duration) *Client {
	return &Client{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		token:   token,
		http:    &http.Client{Timeout: 5 * time.Second},
		ttl:     ttl,
		now:     time.Now,
		cache:   map[string]entry{},
	}
}

// Get devolve as configurações do tenant.
func (c *Client) Get(ctx context.Context, tenantID string) (Settings, error) {
	if c.ttl > 0 {
		c.mu.Lock()
		e, ok := c.cache[tenantID]
		c.mu.Unlock()
		if ok && c.now().Before(e.expiresAt) {
			return e.settings, nil
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.baseURL+"/internal/v1/tenants/"+url.PathEscape(tenantID), nil)
	if err != nil {
		return Settings{}, err
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return Settings{}, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		return Settings{}, ErrTenantNotFound
	default:
		return Settings{}, fmt.Errorf("tenantsettings: identity respondeu %d", resp.StatusCode)
	}
	var s Settings
	if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
		return Settings{}, err
	}
	if c.ttl > 0 {
		c.mu.Lock()
		c.cache[tenantID] = entry{settings: s, expiresAt: c.now().Add(c.ttl)}
		c.mu.Unlock()
	}
	return s, nil
}
