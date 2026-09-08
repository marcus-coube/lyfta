// Package ws mantém o registro de conexões WebSocket ativas desta instância
// do comms e entrega eventos a elas. O fan-out entre instâncias é
// responsabilidade do internal/pubsub (Redis); este pacote só sabe falar com
// as conexões que estão fisicamente presas neste processo — a P3.4 vai
// consultar/ampliar esse registro para decidir se manda push (usuário já
// está com o app aberto) ou não.
package ws

import (
	"sync"

	"github.com/gorilla/websocket"
)

// Conn envolve um *websocket.Conn com o mutex de escrita que o gorilla exige
// (um único goroutine pode escrever por vez numa conexão).
type Conn struct {
	ws *websocket.Conn
	mu sync.Mutex
}

// Write escreve payload (já serializado — o handler HTTP publica o evento em
// JSON antes de chegar aqui, e o Relay do pubsub só repassa bytes crus, sem
// desserializar) como frame de texto, protegido pelo mutex de escrita.
func (c *Conn) Write(payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.ws.WriteMessage(websocket.TextMessage, payload)
}

// WritePing escreve um frame de controle ping, protegido pelo mesmo mutex —
// usado pelo ticker de keepalive do handler.
func (c *Conn) WritePing() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.ws.WriteMessage(websocket.PingMessage, nil)
}

// Close fecha a conexão subjacente.
func (c *Conn) Close() error {
	return c.ws.Close()
}

// NewConn envolve uma conexão já promovida (após o Upgrade).
func NewConn(raw *websocket.Conn) *Conn {
	return &Conn{ws: raw}
}

// Hub é o registro de conexões ativas por usuário (userID -> conjunto de
// conexões — mais de uma quando o mesmo usuário tem o app aberto em mais de
// um device/aba).
type Hub struct {
	mu     sync.Mutex
	byUser map[string]map[*Conn]struct{}
}

// NewHub cria um Hub vazio.
func NewHub() *Hub {
	return &Hub{byUser: make(map[string]map[*Conn]struct{})}
}

// Register associa uma conexão a um usuário.
func (h *Hub) Register(userID string, c *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	set, ok := h.byUser[userID]
	if !ok {
		set = make(map[*Conn]struct{})
		h.byUser[userID] = set
	}
	set[c] = struct{}{}
}

// Unregister remove a conexão do registro do usuário.
func (h *Hub) Unregister(userID string, c *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	set, ok := h.byUser[userID]
	if !ok {
		return
	}
	delete(set, c)
	if len(set) == 0 {
		delete(h.byUser, userID)
	}
}

// ConnsFor devolve uma cópia das conexões ativas do usuário nesta instância.
func (h *Hub) ConnsFor(userID string) []*Conn {
	h.mu.Lock()
	defer h.mu.Unlock()
	set := h.byUser[userID]
	if len(set) == 0 {
		return nil
	}
	out := make([]*Conn, 0, len(set))
	for c := range set {
		out = append(out, c)
	}
	return out
}

// IsOnline diz se o usuário tem ao menos uma conexão ativa nesta instância.
func (h *Hub) IsOnline(userID string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.byUser[userID]) > 0
}

// Deliver entrega payload (JSON cru, ver internal/pubsub.Relay) a todas as
// conexões locais do usuário. Falha de escrita numa conexão não impede a
// entrega às demais — a conexão problemática se anuncia sozinha fechando o
// read loop do handler, que faz o Unregister.
func (h *Hub) Deliver(userID string, payload []byte) {
	for _, c := range h.ConnsFor(userID) {
		_ = c.Write(payload)
	}
}
