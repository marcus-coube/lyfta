package http

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
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
// (internal/ws, só desta instância) e na presença compartilhada via Redis
// (internal/pubsub, entre todas as instâncias) — a P3.4 consulta essa
// segunda para decidir se manda push de message.new (o Hub sozinho não
// serve: ele só sabe das conexões presas neste processo).
type WSHandler struct {
	logger      *slog.Logger
	verifier    *security.JWTVerifier
	hub         *ws.Hub
	redisClient *redis.Client
	upgrader    websocket.Upgrader
}

// NewWSHandler cria o handler de WebSocket sobre o verifier, o Hub e o client
// Redis compartilhados com o resto do serviço.
func NewWSHandler(logger *slog.Logger, verifier *security.JWTVerifier, hub *ws.Hub, redisClient *redis.Client) *WSHandler {
	return &WSHandler{
		logger:      logger,
		verifier:    verifier,
		hub:         hub,
		redisClient: redisClient,
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

	// Presença entre instâncias (P3.4): connID identifica esta conexão dentro
	// do Set Redis do usuário — mais de uma conexão do mesmo usuário (vários
	// devices) marca entradas distintas, e sair de uma não derruba a
	// presença da outra (ver internal/pubsub.PresenceUnmark).
	connID := uuid.NewString()
	if err := pubsub.PresenceMark(r.Context(), h.redisClient, claims.Subject, connID); err != nil {
		h.logger.Error("ws_presence_mark_failed", slog.Any("error", err))
	}
	defer func() {
		if err := pubsub.PresenceUnmark(context.Background(), h.redisClient, claims.Subject, connID); err != nil {
			h.logger.Error("ws_presence_unmark_failed", slog.Any("error", err))
		}
	}()

	_ = raw.SetReadDeadline(time.Now().Add(wsPongWait))
	raw.SetPongHandler(func(string) error {
		return raw.SetReadDeadline(time.Now().Add(wsPongWait))
	})

	stop := make(chan struct{})
	go h.pingLoop(claims.Subject, connID, conn, stop)
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

// pingLoop manda o ping de keepalive e renova a marca de presença (Redis)
// desta conexão a cada intervalo — sem renovar, presenceTTL (90s, bem maior
// que wsPingInterval) expiraria a marca sozinha mesmo com a conexão viva.
func (h *WSHandler) pingLoop(userID, connID string, conn *ws.Conn, stop <-chan struct{}) {
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
			if err := pubsub.PresenceMark(context.Background(), h.redisClient, userID, connID); err != nil {
				h.logger.Error("ws_presence_renew_failed", slog.Any("error", err))
			}
		}
	}
}
