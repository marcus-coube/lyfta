// Package consent consulta o identity sobre o consentimento de um usuário
// (ADR-008 §1, P4.5). É usado só quando o ator não é o titular (o coach lendo
// ou lançando foto de um aluno): para o próprio titular as claims do JWT já
// trazem as finalidades vigentes. Só HTTP com X-Internal-Token (ADR-013 §5).
package consent

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client consulta GET /internal/v1/users/{id}/consents no identity.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
}

// NewClient cria o cliente do identity.
func NewClient(baseURL, token string) *Client {
	return &Client{baseURL: strings.TrimSuffix(baseURL, "/"), token: token, http: &http.Client{Timeout: 5 * time.Second}}
}

// HasPurpose diz se o usuário tem a finalidade vigente na versão atual dos
// termos.
func (c *Client) HasPurpose(ctx context.Context, tenantID, userID, purpose string) (bool, error) {
	target := fmt.Sprintf("%s/internal/v1/users/%s/consents?tenant_id=%s",
		c.baseURL, url.PathEscape(userID), url.QueryEscape(tenantID))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("consent: identity respondeu %d", resp.StatusCode)
	}
	var body struct {
		Purposes []string `json:"purposes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return false, err
	}
	for _, p := range body.Purposes {
		if p == purpose {
			return true, nil
		}
	}
	return false, nil
}
