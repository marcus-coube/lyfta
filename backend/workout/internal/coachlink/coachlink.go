// Package coachlink consulta o identity sobre o vínculo professor↔aluno
// (ADR-016, P4.7). O vínculo vive no identity (ADR-013 §2); aqui só se
// pergunta, por HTTP com X-Internal-Token (ADR-013 §5), e a resposta fica em
// cache em memória por (tenant, coach) durante o TTL — uma reatribuição leva
// até o TTL para valer nesta instância.
//
// Este pacote é duplicado em cada serviço que checa vínculo (workout,
// assessment, comms): nenhum import de código entre serviços.
package coachlink

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

// DefaultTTL é o prazo do cache quando COACH_LINK_CACHE_TTL não é informado.
const DefaultTTL = 30 * time.Second

type cacheKey struct{ tenantID, coachID string }

type cacheEntry struct {
	students  map[string]struct{}
	expiresAt time.Time
}

// Client consulta o vínculo no identity.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
	ttl     time.Duration
	now     func() time.Time

	mu    sync.Mutex
	cache map[cacheKey]cacheEntry
}

// NewClient cria o cliente do identity. ttl <= 0 desliga o cache.
func NewClient(baseURL, token string, ttl time.Duration) *Client {
	return &Client{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		token:   token,
		http:    &http.Client{Timeout: 5 * time.Second},
		ttl:     ttl,
		now:     time.Now,
		cache:   map[cacheKey]cacheEntry{},
	}
}

// StudentsOf devolve o conjunto de alunos vinculados ao coach. Falha do
// identity vira erro (e não é cacheada): quem chama deve fechar o acesso.
func (c *Client) StudentsOf(ctx context.Context, tenantID, coachID string) (map[string]struct{}, error) {
	key := cacheKey{tenantID, coachID}
	if c.ttl > 0 {
		c.mu.Lock()
		entry, ok := c.cache[key]
		c.mu.Unlock()
		if ok && c.now().Before(entry.expiresAt) {
			return entry.students, nil
		}
	}

	target := fmt.Sprintf("%s/internal/v1/coaches/%s/students?tenant_id=%s",
		c.baseURL, url.PathEscape(coachID), url.QueryEscape(tenantID))
	var body struct {
		StudentIDs []string `json:"student_ids"`
	}
	if status, err := c.get(ctx, target, &body); err != nil {
		return nil, err
	} else if status != http.StatusOK {
		return nil, fmt.Errorf("coachlink: identity respondeu %d", status)
	}

	students := make(map[string]struct{}, len(body.StudentIDs))
	for _, id := range body.StudentIDs {
		students[id] = struct{}{}
	}
	if c.ttl > 0 {
		c.mu.Lock()
		c.cache[key] = cacheEntry{students: students, expiresAt: c.now().Add(c.ttl)}
		c.mu.Unlock()
	}
	return students, nil
}

// CanAccessStudent diz se o ator (claims do JWT) pode acessar dados do
// aluno: o owner na claim libera sem chamada; senão o aluno precisa estar no
// conjunto do coach (ADR-016 §2/§3).
func (c *Client) CanAccessStudent(ctx context.Context, tenantID, userID string, roles []string, studentID string) (bool, error) {
	for _, role := range roles {
		if role == "owner" {
			return true, nil
		}
	}
	students, err := c.StudentsOf(ctx, tenantID, userID)
	if err != nil {
		return false, err
	}
	_, ok := students[studentID]
	return ok, nil
}

// VisibleStudents filtra os ids para os que o ator pode ver: owner vê todos
// (sem chamada); coach, só os do conjunto vinculado. Ids fora do vínculo
// somem do resultado, sem erro.
func (c *Client) VisibleStudents(ctx context.Context, tenantID, userID string, roles []string, studentIDs []string) ([]string, error) {
	for _, role := range roles {
		if role == "owner" {
			return studentIDs, nil
		}
	}
	students, err := c.StudentsOf(ctx, tenantID, userID)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(studentIDs))
	for _, id := range studentIDs {
		if _, ok := students[id]; ok {
			out = append(out, id)
		}
	}
	return out, nil
}

func (c *Client) get(ctx context.Context, target string, out any) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK && out != nil {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
			return resp.StatusCode, err
		}
	}
	return resp.StatusCode, nil
}
