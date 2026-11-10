// Package studentdir lê no identity, por M2M (ADR-013 §4/§5), nome e e-mail do
// aluno para a cópia do titular em `billing_customers` (ADR-017 §5), tirada ao
// criar a assinatura. Sem cache: só é chamado na criação.
package studentdir

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// ErrNotFound: aluno inexistente (ou de outro tenant) no identity.
var ErrNotFound = errors.New("studentdir: aluno não encontrado")

// Student é a ficha mínima devolvida por GET /internal/v1/students/{id}.
type Student struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Email  string `json:"email"`
	Status string `json:"status"`
}

// Client consulta o identity.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
}

// NewClient cria o cliente.
func NewClient(baseURL, token string) *Client {
	return &Client{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		token:   token,
		http:    &http.Client{Timeout: 5 * time.Second},
	}
}

// Get devolve nome, e-mail e status do aluno.
func (c *Client) Get(ctx context.Context, tenantID, studentID string) (Student, error) {
	target := fmt.Sprintf("%s/internal/v1/students/%s?tenant_id=%s",
		c.baseURL, url.PathEscape(studentID), url.QueryEscape(tenantID))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return Student{}, err
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return Student{}, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		return Student{}, ErrNotFound
	default:
		return Student{}, fmt.Errorf("studentdir: identity respondeu %d", resp.StatusCode)
	}
	var s Student
	if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
		return Student{}, err
	}
	return s, nil
}
