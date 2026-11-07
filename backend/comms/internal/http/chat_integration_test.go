package http_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"

	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/security"
	"github.com/marcus-coube/lyfta/comms/internal/ws"
)

// Aceite da P3.2: 2 conexões WS trocam mensagem; queda de WS não perde
// mensagem (REST recupera); não lidas zeram no read. O cenário sobe o
// roteador real (repositórios contra o Postgres de dev, fan-out contra o
// Redis de dev) atrás de um httptest.Server — só assim dá pra abrir um
// handshake de WebSocket de verdade (o ResponseRecorder não faz hijack).

func testChatPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_comms?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		chatSkipOrFail(t, "banco indisponível para teste de integração: "+err.Error())
		return nil
	}
	t.Cleanup(pool.Close)
	return pool
}

func testChatRedisURL(t *testing.T) string {
	t.Helper()
	if v := os.Getenv("REDIS_URL"); v != "" {
		return v
	}
	return "redis://localhost:6379/0"
}

func chatSkipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// wsEnvelope espelha o formato público do evento (wsEvent em conversations.go
// é não-exportado de propósito — este teste é caixa-preta pelo contrato
// HTTP/WS, não pelos tipos internos do pacote).
type wsEnvelope struct {
	Type           string `json:"type"`
	ConversationID string `json:"conversation_id"`
	Message        *struct {
		ID       string `json:"id"`
		SenderID string `json:"sender_id"`
		Type     string `json:"type"`
		Body     string `json:"body"`
	} `json:"message"`
	ReaderID   string   `json:"reader_id"`
	MessageIDs []string `json:"message_ids"`
}

type conversationEnvelope struct {
	ID          string `json:"id"`
	StudentID   string `json:"student_id"`
	CoachID     string `json:"coach_id"`
	UnreadCount int    `json:"unread_count"`
}

type conversationListEnvelope struct {
	Items []conversationEnvelope `json:"items"`
}

type messageListEnvelope struct {
	Items []struct {
		ID     string `json:"id"`
		Body   string `json:"body"`
		Sender string `json:"sender_id"`
	} `json:"items"`
}

func TestChatEndToEnd(t *testing.T) {
	pool := testChatPool(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	redisClient, err := pubsub.NewClient(ctx, testChatRedisURL(t))
	if err != nil {
		chatSkipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = redisClient.Close() })

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	verifier, err := security.NewJWTVerifier(pemFromPublicKey(t, pub))
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}

	logger := slog.New(slog.DiscardHandler)
	hub := ws.NewHub()
	go pubsub.Relay(ctx, redisClient, logger, hub.Deliver)

	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)
	linker := newFakeLinker()
	conversationHandler := chttp.NewConversationHandler(logger, conversations, messages, nil, redisClient, nil, linker)
	var mediaHandler *chttp.MediaHandler
	wsHandler := chttp.NewWSHandler(logger, verifier, hub, redisClient)
	var checkinHandler *chttp.CheckinHandler

	router := chttp.NewRouter(logger, []string{"*"}, verifier, "", conversationHandler, mediaHandler, wsHandler, checkinHandler, nil, nil)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)

	tenantID := uuid.NewString()
	studentID := uuid.NewString()
	coachID := uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, coachID, []string{"coach"})
	linker.link(coachID, studentID)

	// 1. Coach abre a conversa com o aluno.
	var convResp conversationEnvelope
	doJSON(t, server, http.MethodPost, "/v1/conversations", coachToken,
		map[string]string{"student_id": studentID}, &convResp)
	if convResp.ID == "" {
		t.Fatal("esperava id de conversa")
	}
	convID := convResp.ID

	// 2. As duas pontas conectam no WS e ficam registradas no Hub (confirmado
	// por polling — o Upgrade só devolve pro Dial depois do handshake, mas o
	// Register no servidor roda logo em seguida, então não é garantido que já
	// tenha rodado no instante em que Dial retorna).
	studentConn := dialWS(t, server, studentToken)
	coachConn := dialWS(t, server, coachToken)
	waitOnline(t, hub, studentID)
	waitOnline(t, hub, coachID)

	// 3. Aluno manda mensagem de texto — as duas conexões (aluno e coach)
	// recebem message.new via WS, porque o publish alcança os dois
	// participantes.
	var msg1 struct {
		ID string `json:"id"`
	}
	doJSON(t, server, http.MethodPost, "/v1/conversations/"+convID+"/messages", studentToken,
		map[string]string{"type": "text", "body": "oi coach"}, &msg1)

	evCoach := readWSEvent(t, coachConn)
	if evCoach.Type != "message.new" || evCoach.Message == nil || evCoach.Message.Body != "oi coach" {
		t.Fatalf("coach deveria receber message.new com o texto do aluno, veio %+v", evCoach)
	}
	evStudent := readWSEvent(t, studentConn)
	if evStudent.Type != "message.new" || evStudent.Message == nil || evStudent.Message.Body != "oi coach" {
		t.Fatalf("aluno deveria receber o eco do próprio message.new, veio %+v", evStudent)
	}

	// 4. Queda de WS do coach (rede caiu) — o coach fica sem receber eventos
	// em tempo real, mas a mensagem que chegar nesse meio tempo não pode se
	// perder: ela é recuperável via REST assim que ele reconectar.
	_ = coachConn.Close()
	waitOffline(t, hub, coachID)

	doJSON(t, server, http.MethodPost, "/v1/conversations/"+convID+"/messages", coachToken,
		map[string]string{"type": "text", "body": "depois de cair"}, &struct {
			ID string `json:"id"`
		}{})

	var history messageListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/conversations/"+convID+"/messages", coachToken, nil, &history)
	if !containsBody(history, "depois de cair") {
		t.Fatalf("REST deveria recuperar a mensagem enviada com o WS do coach caído: %+v", history)
	}
	if !containsBody(history, "oi coach") {
		t.Fatalf("histórico REST deveria conter as duas mensagens: %+v", history)
	}

	// 5. Não lidas: antes do read, o coach tem 1 mensagem não lida (a do
	// aluno) — a própria dele não conta.
	var beforeRead conversationListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/conversations", coachToken, nil, &beforeRead)
	if unread := unreadFor(beforeRead, convID); unread != 1 {
		t.Fatalf("coach deveria ter 1 não lida antes do read, tinha %d", unread)
	}

	doJSON(t, server, http.MethodPost, "/v1/conversations/"+convID+"/read", coachToken, nil, &struct {
		Marked int `json:"marked"`
	}{})

	var afterRead conversationListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/conversations", coachToken, nil, &afterRead)
	if unread := unreadFor(afterRead, convID); unread != 0 {
		t.Fatalf("não lidas deveriam zerar depois do read, ficou %d", unread)
	}

	_ = studentConn.Close()
}

func pemFromPublicKey(t *testing.T, pub ed25519.PublicKey) string {
	t.Helper()
	pubBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal chave pública: %v", err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes}))
}

func dialWS(t *testing.T, server *httptest.Server, token string) *websocket.Conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws?token=" + token
	conn, resp, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("conectar WS: %v", err)
	}
	if resp != nil {
		_ = resp.Body.Close()
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn
}

func waitOnline(t *testing.T, hub *ws.Hub, userID string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if hub.IsOnline(userID) {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("usuário %s nunca apareceu como online no Hub", userID)
}

func waitOffline(t *testing.T, hub *ws.Hub, userID string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !hub.IsOnline(userID) {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("usuário %s nunca saiu do Hub depois do Close", userID)
}

func readWSEvent(t *testing.T, conn *websocket.Conn) wsEnvelope {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("ler evento do WS: %v", err)
	}
	var ev wsEnvelope
	if err := json.Unmarshal(data, &ev); err != nil {
		t.Fatalf("decodificar evento do WS: %v — payload: %s", err, data)
	}
	return ev
}

func doJSON(t *testing.T, server *httptest.Server, method, path, token string, body any, out any) {
	t.Helper()
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("serializar corpo: %v", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, server.URL+path, reader)
	if err != nil {
		t.Fatalf("montar requisição: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ler resposta de %s %s: %v", method, path, err)
	}
	if resp.StatusCode >= 300 {
		t.Fatalf("%s %s devolveu %d: %s", method, path, resp.StatusCode, respBody)
	}
	if out != nil && len(respBody) > 0 {
		if err := json.Unmarshal(respBody, out); err != nil {
			t.Fatalf("decodificar resposta de %s %s: %v — corpo: %s", method, path, err, respBody)
		}
	}
}

func containsBody(list messageListEnvelope, body string) bool {
	for _, m := range list.Items {
		if m.Body == body {
			return true
		}
	}
	return false
}

func unreadFor(list conversationListEnvelope, conversationID string) int {
	for _, c := range list.Items {
		if c.ID == conversationID {
			return c.UnreadCount
		}
	}
	return -1
}

// doJSONStatus é a variante de doJSON que não falha o teste em status de
// erro — usada pelos casos negativos abaixo, onde o erro é o resultado
// esperado.
func doJSONStatus(t *testing.T, server *httptest.Server, method, path, token string, body any) int {
	t.Helper()
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("serializar corpo: %v", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, server.URL+path, reader)
	if err != nil {
		t.Fatalf("montar requisição: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.ReadAll(resp.Body)
	return resp.StatusCode
}

// TestChatAuthorizationAndValidation cobre os casos de borda que o roteiro
// feliz do TestChatEndToEnd não passa: mensagem de tipo inválido, imagem sem
// media_key, e um usuário de fora da conversa tentando ler/escrever nela —
// "sou participante" é a autorização inteira do chat (não há porta
// /me × /students/{id} aqui, ver router.go).
func TestChatAuthorizationAndValidation(t *testing.T) {
	pool := testChatPool(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	redisClient, err := pubsub.NewClient(ctx, testChatRedisURL(t))
	if err != nil {
		chatSkipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return
	}
	t.Cleanup(func() { _ = redisClient.Close() })

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("gerar par de chaves: %v", err)
	}
	verifier, err := security.NewJWTVerifier(pemFromPublicKey(t, pub))
	if err != nil {
		t.Fatalf("criar verifier: %v", err)
	}

	logger := slog.New(slog.DiscardHandler)
	hub := ws.NewHub()
	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)
	conversationHandler := chttp.NewConversationHandler(logger, conversations, messages, nil, redisClient, nil, newAllowAllLinker())
	var mediaHandler *chttp.MediaHandler
	wsHandler := chttp.NewWSHandler(logger, verifier, hub, redisClient)
	var checkinHandler *chttp.CheckinHandler
	router := chttp.NewRouter(logger, []string{"*"}, verifier, "", conversationHandler, mediaHandler, wsHandler, checkinHandler, nil, nil)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)

	tenantID := uuid.NewString()
	studentID := uuid.NewString()
	coachID := uuid.NewString()
	outsiderID := uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, coachID, []string{"coach"})
	outsiderToken := signToken(t, priv, tenantID, outsiderID, []string{"coach"})

	var conv conversationEnvelope
	doJSON(t, server, http.MethodPost, "/v1/conversations", coachToken,
		map[string]string{"student_id": studentID}, &conv)

	// Só coach/owner pode abrir conversa nova.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/conversations", studentToken,
		map[string]string{"student_id": studentID}); status != http.StatusForbidden {
		t.Fatalf("aluno abrindo conversa deveria ser 403, veio %d", status)
	}

	// Tipo de mensagem desconhecido.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/conversations/"+conv.ID+"/messages", studentToken,
		map[string]string{"type": "audio", "body": "x"}); status != http.StatusBadRequest {
		t.Fatalf("tipo inválido deveria ser 400, veio %d", status)
	}

	// Imagem sem media_key.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/conversations/"+conv.ID+"/messages", studentToken,
		map[string]string{"type": "image"}); status != http.StatusBadRequest {
		t.Fatalf("imagem sem media_key deveria ser 400, veio %d", status)
	}

	// Imagem com media_key de outra conversa (par de segurança do presign).
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/conversations/"+conv.ID+"/messages", studentToken,
		map[string]string{"type": "image", "media_key": "tenants/" + tenantID + "/chat/outra-conversa/foo.jpg"}); status != http.StatusUnprocessableEntity {
		t.Fatalf("media_key de outra conversa deveria ser 422, veio %d", status)
	}

	// Usuário de fora não lê nem escreve na conversa.
	if status := doJSONStatus(t, server, http.MethodGet, "/v1/conversations/"+conv.ID+"/messages", outsiderToken, nil); status != http.StatusForbidden {
		t.Fatalf("outsider lendo histórico deveria ser 403, veio %d", status)
	}
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/conversations/"+conv.ID+"/messages", outsiderToken,
		map[string]string{"type": "text", "body": "intruso"}); status != http.StatusForbidden {
		t.Fatalf("outsider escrevendo deveria ser 403, veio %d", status)
	}

	// Conversa inexistente é 404, não 403 (não revela se a conversa é de
	// outro tenant ou simplesmente não existe).
	if status := doJSONStatus(t, server, http.MethodGet, "/v1/conversations/"+uuid.NewString()+"/messages", coachToken, nil); status != http.StatusNotFound {
		t.Fatalf("conversa inexistente deveria ser 404, veio %d", status)
	}
}
