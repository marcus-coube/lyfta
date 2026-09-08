package http

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/gorilla/websocket"

	"github.com/marcus-coube/lyfta/comms/internal/security"
	"github.com/marcus-coube/lyfta/comms/internal/ws"
)

const (
	// wsPingInterval é o intervalo do ping de keepalive do servidor — detecta
	// conexão morta (rede caiu sem fechar o socket) antes do próximo envio.
	wsPingInterval = 30 * time.Second
	// wsPongWait é o prazo para o cliente responder ao ping (ou mandar
	// qualquer frame) antes do servidor considerar a conexão morta.
	wsPongWait = 60 * time.Second
)

// WSHandler promove a conexão WebSocket do chat (P3.2) e a registra no Hub
// (internal/ws) — o registro de conexões que a P3.4 vai consultar para
// decidir se manda push (destinatário já está com o app aberto).
type WSHandler struct {
	logger   *slog.Logger
	verifier *security.JWTVerifier
	hub      *ws.Hub
	upgrader websocket.Upgrader
}

// NewWSHandler cria o handler de WebSocket sobre o verifier e o Hub
// compartilhados com o resto do serviço.
func NewWSHandler(logger *slog.Logger, verifier *security.JWTVerifier, hub *ws.Hub) *WSHandler {
	return &WSHandler{
		logger:   logger,
		verifier: verifier,
		hub:      hub,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			// O handshake de upgrade não passa pelo cors.Handler das rotas REST
			// (não é uma requisição comum). Sem API gateway no MVP (ADR-013 §6)
			// e com o token já autenticando o usuário, aceitar qualquer origem
			// aqui não abre superfície nova — o mesmo token expõe os mesmos
			// dados via REST de qualquer origem.
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

// Serve autentica pelo token da query string (GET /ws?token=... — o
// handshake de WS do browser não manda header customizado), promove a
// conexão e a mantém registrada até o cliente desconectar. O servidor nunca
// lê conteúdo de negócio do cliente por aqui: enviar mensagem é sempre REST
// (POST .../messages) — o WS só entrega o que os handlers REST publicam
// (internal/pubsub.Relay alimenta o Hub).
func (h *WSHandler) Serve(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeError(w, errUnauthenticated())
		return
	}
	claims, err := h.verifier.Parse(token)
	if err != nil || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	raw, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		// Upgrade já escreve a resposta HTTP de erro sozinho antes de falhar.
		h.logger.Warn("ws_upgrade_failed", slog.Any("error", err))
		return
	}

	conn := ws.NewConn(raw)
	h.hub.Register(claims.Subject, conn)
	defer h.hub.Unregister(claims.Subject, conn)

	_ = raw.SetReadDeadline(time.Now().Add(wsPongWait))
	raw.SetPongHandler(func(string) error {
		return raw.SetReadDeadline(time.Now().Add(wsPongWait))
	})

	stop := make(chan struct{})
	go h.pingLoop(conn, stop)
	defer close(stop)

	// O cliente não manda conteúdo de negócio, mas o loop de leitura precisa
	// rodar mesmo assim: é o que dispara o PongHandler acima e é o único jeito
	// de detectar que o socket fechou (ReadMessage devolve erro).
	for {
		if _, _, err := raw.ReadMessage(); err != nil {
			break
		}
	}
	_ = conn.Close()
}

func (h *WSHandler) pingLoop(conn *ws.Conn, stop <-chan struct{}) {
	ticker := time.NewTicker(wsPingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			if err := conn.WritePing(); err != nil {
				return
			}
		}
	}
}
