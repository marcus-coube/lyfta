package http_test

import (
	"context"
	"crypto/ed25519"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	chttp "github.com/marcus-coube/lyfta/comms/internal/http"
	"github.com/marcus-coube/lyfta/comms/internal/media"
	"github.com/marcus-coube/lyfta/comms/internal/pubsub"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/security"
	"github.com/marcus-coube/lyfta/comms/internal/ws"
)

// Aceite do P3.3: duplicata de check-in não cria segundo registro; listagem
// do coach ordena não revisados primeiro. Sobe o roteador real (Postgres +
// Redis de dev) atrás de httptest.NewServer, mesmo padrão do
// chat_integration_test.go.

type checkinEnvelope struct {
	ID              string     `json:"id"`
	StudentID       string     `json:"student_id"`
	SessionClientID string     `json:"session_client_id"`
	Rating          int        `json:"rating"`
	Difficulty      int        `json:"difficulty"`
	Pain            string     `json:"pain"`
	ReviewedBy      string     `json:"reviewed_by"`
	ReviewedAt      *time.Time `json:"reviewed_at"`
}

type checkinListEnvelope struct {
	Items      []checkinEnvelope `json:"items"`
	NextCursor string            `json:"next_cursor"`
}

// newCheckinTestServer sobe o roteador completo (chat + check-ins) com
// repositórios reais — os testes de check-in também precisam do
// ConversationRepo; o gancho de dor forte consulta o coach atual do aluno no
// vínculo (ver CheckinHandler.notifyCoachOfStrongPain).
func newCheckinTestServer(t *testing.T) (*httptest.Server, ed25519.PrivateKey, *ws.Hub, *fakeLinker) {
	t.Helper()
	linker := newAllowAllLinker()
	server, priv, hub := newServerWithLinker(t, linker)
	return server, priv, hub, linker
}

// newServerWithLinker é o roteador completo com o vínculo coach↔aluno
// injetado: o fakeLinker dos testes comuns ou o cliente coachlink contra um
// identity fake (coach_link_test.go).
func newServerWithLinker(t *testing.T, linker chttp.StudentLinker) (*httptest.Server, ed25519.PrivateKey, *ws.Hub) {
	t.Helper()
	pool := testChatPool(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	redisClient, err := pubsub.NewClient(ctx, testChatRedisURL(t))
	if err != nil {
		chatSkipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return nil, nil, nil
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
	checkins := repo.NewCheckinRepo(pool)
	conversationHandler := chttp.NewConversationHandler(logger, conversations, messages, nil, redisClient, nil, linker)
	// Assinar é operação offline: o presigner monta a URL sem falar com o
	// storage (mesmo critério do workout/assessment).
	presigner, err := media.NewPresigner(media.Config{
		Endpoint: "http://localhost:9000", Region: "us-east-1", Bucket: "lyfta-media",
		AccessKey: "minioadmin", SecretKey: "minioadmin", UsePathStyle: true,
	})
	if err != nil {
		t.Fatalf("criar presigner: %v", err)
	}
	mediaHandler := chttp.NewMediaHandler(logger, conversations, presigner, linker)
	wsHandler := chttp.NewWSHandler(logger, verifier, hub, redisClient)
	checkinHandler := chttp.NewCheckinHandler(logger, checkins, linker, redisClient, nil)

	router := chttp.NewRouter(logger, []string{"*"}, verifier, "", conversationHandler, mediaHandler, wsHandler, checkinHandler, nil, nil)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)
	return server, priv, hub
}

func TestCheckinCreateIsIdempotentOverHTTP(t *testing.T) {
	server, priv, _, _ := newCheckinTestServer(t)
	tenantID, studentID := uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	sessionClientID := uuid.NewString()

	body := map[string]any{
		"session_client_id": sessionClientID, "rating": 5, "difficulty": 3, "pain": "none",
	}
	var first checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, body, &first)
	if first.StudentID != studentID {
		t.Fatalf("student_id deveria vir da claim, veio %q", first.StudentID)
	}

	// Reenvio com dados diferentes: mesmo session_client_id, não deveria
	// criar um segundo registro nem trocar os dados do primeiro.
	dup := map[string]any{
		"session_client_id": sessionClientID, "rating": 1, "difficulty": 1, "pain": "strong",
	}
	var second checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, dup, &second)
	if second.ID != first.ID {
		t.Fatalf("reenvio deveria devolver o mesmo check-in: %s != %s", first.ID, second.ID)
	}
	if second.Rating != 5 || second.Pain != "none" {
		t.Fatalf("reenvio não deveria sobrescrever o check-in original, veio %+v", second)
	}

	coachToken := signToken(t, priv, tenantID, uuid.NewString(), []string{"owner"})
	var list checkinListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/checkins?student_id="+studentID, coachToken, nil, &list)
	if len(list.Items) != 1 {
		t.Fatalf("reenvio não deveria criar um segundo registro, listagem trouxe %d", len(list.Items))
	}
}

func TestCheckinStudentIDAlwaysComesFromClaim(t *testing.T) {
	server, priv, _, _ := newCheckinTestServer(t)
	tenantID, studentID, spoofedID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})

	var created checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"student_id": spoofedID, "session_client_id": uuid.NewString(), "rating": 4, "difficulty": 2, "pain": "mild",
	}, &created)
	if created.StudentID != studentID {
		t.Fatalf("student_id no corpo deveria ser ignorado, esperava %s, veio %s", studentID, created.StudentID)
	}
}

func TestCheckinListOrdersPendingFirstOverHTTP(t *testing.T) {
	server, priv, _, _ := newCheckinTestServer(t)
	tenantID, studentID := uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, uuid.NewString(), []string{"coach"})

	var reviewed checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 3, "difficulty": 3, "pain": "none",
	}, &reviewed)
	doJSON(t, server, http.MethodPost, "/v1/checkins/"+reviewed.ID+"/review", coachToken, nil, &struct{}{})

	time.Sleep(2 * time.Millisecond)
	var pending checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 2, "difficulty": 4, "pain": "mild",
	}, &pending)

	var list checkinListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/checkins?student_id="+studentID, coachToken, nil, &list)
	if len(list.Items) != 2 {
		t.Fatalf("esperava 2 check-ins, veio %d", len(list.Items))
	}
	if list.Items[0].ID != pending.ID || list.Items[0].ReviewedAt != nil {
		t.Fatalf("o primeiro item deveria ser o não revisado, veio %+v", list.Items[0])
	}
	if list.Items[1].ID != reviewed.ID || list.Items[1].ReviewedAt == nil {
		t.Fatalf("o segundo item deveria ser o já revisado, veio %+v", list.Items[1])
	}
}

func TestCheckinReviewOverHTTP(t *testing.T) {
	server, priv, _, _ := newCheckinTestServer(t)
	tenantID, studentID, coachID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, coachID, []string{"coach"})

	var created checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 4, "difficulty": 4, "pain": "none",
	}, &created)

	var reviewed checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins/"+created.ID+"/review", coachToken, nil, &reviewed)
	if reviewed.ReviewedBy != coachID || reviewed.ReviewedAt == nil {
		t.Fatalf("esperava reviewed_by=%s com reviewed_at preenchido, veio %+v", coachID, reviewed)
	}
}

func TestCheckinAuthorizationAndValidation(t *testing.T) {
	server, priv, _, _ := newCheckinTestServer(t)
	tenantID, studentID := uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, uuid.NewString(), []string{"coach"})

	// Rating fora do intervalo.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 6, "difficulty": 3, "pain": "none",
	}); status != http.StatusBadRequest {
		t.Fatalf("rating fora do intervalo deveria ser 400, veio %d", status)
	}

	// Dor desconhecida.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 3, "difficulty": 3, "pain": "muita",
	}); status != http.StatusBadRequest {
		t.Fatalf("pain inválido deveria ser 400, veio %d", status)
	}

	// session_client_id ausente.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"rating": 3, "difficulty": 3, "pain": "none",
	}); status != http.StatusBadRequest {
		t.Fatalf("session_client_id ausente deveria ser 400, veio %d", status)
	}

	// Aluno não pode listar nem revisar (só coach/owner).
	if status := doJSONStatus(t, server, http.MethodGet, "/v1/checkins?student_id="+studentID, studentToken, nil); status != http.StatusForbidden {
		t.Fatalf("aluno listando check-ins deveria ser 403, veio %d", status)
	}
	var created checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 3, "difficulty": 3, "pain": "none",
	}, &created)
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/checkins/"+created.ID+"/review", studentToken, nil); status != http.StatusForbidden {
		t.Fatalf("aluno revisando check-in deveria ser 403, veio %d", status)
	}

	// Revisar id inexistente é 404.
	if status := doJSONStatus(t, server, http.MethodPost, "/v1/checkins/"+uuid.NewString()+"/review", coachToken, nil); status != http.StatusNotFound {
		t.Fatalf("revisar id inexistente deveria ser 404, veio %d", status)
	}
}

// TestCheckinStrongPainNotifiesCoachWithOpenConversation: dor `strong` publica
// no canal Redis do coach atual do aluno, no mesmo formato dos eventos de
// chat — quem estiver com o WS conectado recebe na hora.
func TestCheckinStrongPainNotifiesCoachWithOpenConversation(t *testing.T) {
	server, priv, hub, linker := newCheckinTestServer(t)
	tenantID, studentID, coachID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	studentToken := signToken(t, priv, tenantID, studentID, []string{"student"})
	coachToken := signToken(t, priv, tenantID, coachID, []string{"coach"})

	// O coach atual do aluno vem do identity (ADR-016): o push de dor forte vai
	// só para ele, tenha ou não conversa aberta.
	linker.link(coachID, studentID)
	doJSON(t, server, http.MethodPost, "/v1/conversations", coachToken,
		map[string]string{"student_id": studentID}, &struct {
			ID string `json:"id"`
		}{})

	coachConn := dialWS(t, server, coachToken)
	waitOnline(t, hub, coachID)

	var created checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", studentToken, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 1, "difficulty": 5, "pain": "strong",
	}, &created)

	ev := readCheckinPainEvent(t, coachConn)
	if ev.Type != "checkin.pain_strong" || ev.CheckinID != created.ID || ev.StudentID != studentID {
		t.Fatalf("coach deveria receber checkin.pain_strong para o check-in criado, veio %+v", ev)
	}
}

type checkinPainEventEnvelope struct {
	Type      string `json:"type"`
	CheckinID string `json:"checkin_id"`
	StudentID string `json:"student_id"`
	Pain      string `json:"pain"`
}

func readCheckinPainEvent(t *testing.T, conn *websocket.Conn) checkinPainEventEnvelope {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("ler evento do WS: %v", err)
	}
	var ev checkinPainEventEnvelope
	if err := json.Unmarshal(data, &ev); err != nil {
		t.Fatalf("decodificar evento do WS: %v — payload: %s", err, data)
	}
	return ev
}
