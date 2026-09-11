// Package workoutclient é o cliente HTTP que o comms usa para consultar o
// workout via M2M (ADR-013 §4/§5) — o job diário de "treino pendente" (P3.4)
// precisa saber quem tem plano ativo e não treinou hoje, e essa pergunta só o
// workout sabe responder. Duplicar os tipos de request/response em vez de
// importar o pacote do workout é o certo (ADR-013 §2: nenhum import de
// código entre serviços — cada serviço vai virar um repositório próprio).
package workoutclient

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

// Client fala com o serviço workout autenticado por X-Internal-Token
// (ADR-013 §4, mesmo mecanismo dos demais serviços — ver
// backend/README.md § Stack pinada).
type Client struct {
	baseURL       string
	internalToken string
	httpClient    *http.Client
}

// NewClient cria um Client apontando para baseURL (ex.: http://localhost:8082,
// env WORKOUT_BASE_URL do comms).
func NewClient(baseURL, internalToken string) *Client {
	return &Client{
		baseURL:       baseURL,
		internalToken: internalToken,
		httpClient:    &http.Client{Timeout: 10 * time.Second},
	}
}

// PendingStudent é um item de GET /internal/v1/pending-students — aluno com
// plano ativo e sem sessão registrada no intervalo consultado.
type PendingStudent struct {
	TenantID  string `json:"tenant_id"`
	StudentID string `json:"student_id"`
}

type pendingStudentsResponse struct {
	Items []PendingStudent `json:"items"`
}

// PendingStudents chama GET /internal/v1/pending-students?since=&until= — o
// intervalo [since, until) é decidido pelo comms (internal/job: "hoje" no
// timezone padrão configurado, ver Notas de execução da P3.4), não pelo
// workout, que só responde à pergunta com a janela que recebe.
func (c *Client) PendingStudents(ctx context.Context, since, until time.Time) ([]PendingStudent, error) {
	q := url.Values{}
	q.Set("since", since.UTC().Format(time.RFC3339))
	q.Set("until", until.UTC().Format(time.RFC3339))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/internal/v1/pending-students?"+q.Encode(), nil)
	if err != nil {
		return nil, fmt.Errorf("workoutclient: montar requisição: %w", err)
	}
	req.Header.Set("X-Internal-Token", c.internalToken)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("workoutclient: chamar pending-students: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("workoutclient: pending-students devolveu %d", resp.StatusCode)
	}

	var body pendingStudentsResponse
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("workoutclient: decodificar resposta: %w", err)
	}
	return body.Items, nil
}
