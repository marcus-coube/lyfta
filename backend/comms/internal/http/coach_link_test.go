package http_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/coachlink"
)

// fakeIdentity serve o M2M de vínculo (ADR-016 §3) a partir de um mapa
// aluno → coach que o teste muda para simular reatribuição.
type fakeIdentity struct {
	mu      sync.Mutex
	coachOf map[string]string
	down    bool
	server  *httptest.Server
}

func newFakeIdentity(t *testing.T) *fakeIdentity {
	t.Helper()
	f := &fakeIdentity{coachOf: map[string]string{}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.down {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if r.Header.Get("X-Internal-Token") != "interno" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		path := r.URL.Path
		switch {
		case strings.HasPrefix(path, "/internal/v1/coaches/") && strings.HasSuffix(path, "/students"):
			coach := strings.TrimSuffix(strings.TrimPrefix(path, "/internal/v1/coaches/"), "/students")
			ids := []string{}
			for student, c := range f.coachOf {
				if c == coach {
					ids = append(ids, student)
				}
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"student_ids": ids})
		case strings.HasPrefix(path, "/internal/v1/students/") && strings.HasSuffix(path, "/coach"):
			student := strings.TrimSuffix(strings.TrimPrefix(path, "/internal/v1/students/"), "/coach")
			coach, ok := f.coachOf[student]
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"coach_id": coach})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeIdentity) assign(student, coach string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.coachOf[student] = coach
}

func (f *fakeIdentity) setDown(down bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.down = down
}

// doRaw faz a requisição e devolve status + `code` do erro (se houver) + corpo.
func doRaw(t *testing.T, server *httptest.Server, method, path, token string, body any) (int, string, []byte) {
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
	raw, _ := io.ReadAll(resp.Body)
	var e struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(raw, &e)
	return resp.StatusCode, e.Code, raw
}

// TestCoachLinkCrossCoach cobre o Aceite do P4.7 no comms: o coach B recebe
// 404 student_not_found no que é do aluno de A e não o vê na fila de check-ins;
// o owner acessa tudo; a reatribuição troca quem acessa (o ex-coach perde a
// conversa, o aluno segue lendo o histórico); o push de dor vai só ao coach
// atual; identity fora do ar fecha o acesso (500).
func TestCoachLinkCrossCoach(t *testing.T) {
	identity := newFakeIdentity(t)
	// TTL 0: a reatribuição vale na hora; o TTL em si é testado no coachlink.
	server, priv, hub := newServerWithLinker(t, coachlink.NewClient(identity.server.URL, "interno", 0))

	tenant := uuid.NewString()
	coachA, coachB, owner, student := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	tokA := signToken(t, priv, tenant, coachA, []string{"coach"})
	tokB := signToken(t, priv, tenant, coachB, []string{"coach"})
	tokOwner := signToken(t, priv, tenant, owner, []string{"owner", "coach"})
	tokStudent := signToken(t, priv, tenant, student, []string{"student"})
	identity.assign(student, coachA)

	// A abre a conversa, o aluno fala e faz um check-in.
	var convA conversationEnvelope
	doJSON(t, server, http.MethodPost, "/v1/conversations", tokA, map[string]string{"student_id": student}, &convA)
	doJSON(t, server, http.MethodPost, "/v1/conversations/"+convA.ID+"/messages", tokStudent,
		map[string]string{"type": "text", "body": "oi coach A"}, &struct{}{})
	var checkin checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", tokStudent, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 4, "difficulty": 3, "pain": "none",
	}, &checkin)

	expect404 := func(who, method, path, token string, body any) {
		t.Helper()
		status, code, raw := doRaw(t, server, method, path, token, body)
		if status != http.StatusNotFound || code != "student_not_found" {
			t.Errorf("%s: %s %s deveria ser 404 student_not_found, veio %d %s", who, method, path, status, raw)
		}
	}

	// Coach B: nada do aluno de A, e a fila dele não mostra o check-in.
	expect404("coach B", http.MethodPost, "/v1/conversations", tokB, map[string]string{"student_id": student})
	expect404("coach B", http.MethodGet, "/v1/checkins?student_id="+student, tokB, nil)
	expect404("coach B", http.MethodPost, "/v1/checkins/"+checkin.ID+"/review", tokB, nil)
	var queueB checkinListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/checkins", tokB, nil, &queueB)
	if len(queueB.Items) != 0 {
		t.Errorf("a fila do coach B deveria estar vazia, veio %d item(ns)", len(queueB.Items))
	}

	// Owner acessa tudo, sem vínculo.
	var queueOwner checkinListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/checkins", tokOwner, nil, &queueOwner)
	if len(queueOwner.Items) != 1 {
		t.Errorf("owner deveria ver o check-in do tenant, veio %d", len(queueOwner.Items))
	}
	var ownerConv conversationEnvelope
	doJSON(t, server, http.MethodPost, "/v1/conversations", tokOwner, map[string]string{"student_id": student}, &ownerConv)

	// Reatribuição: o aluno passa para B.
	identity.assign(student, coachB)

	// O ex-coach A perde a conversa (404 em ler, enviar, ler-marcar, presign),
	// some da lista dele e da fila; o aluno segue lendo o histórico.
	expect404("ex-coach A", http.MethodGet, "/v1/conversations/"+convA.ID+"/messages", tokA, nil)
	expect404("ex-coach A", http.MethodPost, "/v1/conversations/"+convA.ID+"/messages", tokA, map[string]string{"type": "text", "body": "ainda aqui?"})
	expect404("ex-coach A", http.MethodPost, "/v1/conversations/"+convA.ID+"/read", tokA, nil)
	expect404("ex-coach A", http.MethodPost, "/v1/conversations/"+convA.ID+"/media/presign", tokA, map[string]any{"content_type": "image/jpeg", "size_bytes": 1000})
	expect404("ex-coach A", http.MethodGet, "/v1/checkins?student_id="+student, tokA, nil)
	var listA conversationListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/conversations", tokA, nil, &listA)
	if unreadFor(listA, convA.ID) != -1 {
		t.Errorf("a conversa com o ex-aluno não deveria aparecer na lista do coach A")
	}
	var history messageListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/conversations/"+convA.ID+"/messages", tokStudent, nil, &history)
	if !containsBody(history, "oi coach A") {
		t.Errorf("o aluno deveria seguir lendo o histórico da conversa antiga: %+v", history)
	}

	// B passa a ver: abre a conversa dele e vê o check-in na fila e revisa.
	var convB conversationEnvelope
	doJSON(t, server, http.MethodPost, "/v1/conversations", tokB, map[string]string{"student_id": student}, &convB)
	if convB.ID == convA.ID {
		t.Errorf("a conversa do coach B deveria ser outra")
	}
	var queueB2 checkinListEnvelope
	doJSON(t, server, http.MethodGet, "/v1/checkins", tokB, nil, &queueB2)
	if len(queueB2.Items) != 1 {
		t.Errorf("a fila do coach B deveria ter o check-in, veio %d", len(queueB2.Items))
	}
	doJSON(t, server, http.MethodPost, "/v1/checkins/"+checkin.ID+"/review", tokB, nil, &struct{}{})

	// Dor forte: só o coach atual (B) recebe o evento no WS; o ex-coach A não.
	connA := dialWS(t, server, tokA)
	connB := dialWS(t, server, tokB)
	waitOnline(t, hub, coachA)
	waitOnline(t, hub, coachB)
	var strong checkinEnvelope
	doJSON(t, server, http.MethodPost, "/v1/checkins", tokStudent, map[string]any{
		"session_client_id": uuid.NewString(), "rating": 1, "difficulty": 5, "pain": "strong",
	}, &strong)
	if ev := readCheckinPainEvent(t, connB); ev.CheckinID != strong.ID {
		t.Errorf("coach B deveria receber a dor forte: %+v", ev)
	}
	_ = connA.SetReadDeadline(time.Now().Add(400 * time.Millisecond))
	if _, data, err := connA.ReadMessage(); err == nil {
		t.Errorf("o ex-coach A não deveria receber a dor forte: %s", data)
	}

	// Identity fora do ar: o acesso do coach fecha com 500; o owner não depende.
	identity.setDown(true)
	if status, _, _ := doRaw(t, server, http.MethodGet, "/v1/checkins", tokB, nil); status != http.StatusInternalServerError {
		t.Errorf("identity fora: esperava 500, veio %d", status)
	}
	if status, _, _ := doRaw(t, server, http.MethodGet, "/v1/checkins", tokOwner, nil); status != http.StatusOK {
		t.Errorf("owner não depende do identity: %d", status)
	}
}

// TestStudentStartsConversationWithOwnCoach: o aluno abre (ou recupera) a
// conversa com o professor vinculado — o corpo é ignorado, então ele não
// escolhe com quem fala; sem professor, 409 no_coach; identity fora, 500.
func TestStudentStartsConversationWithOwnCoach(t *testing.T) {
	identity := newFakeIdentity(t)
	server, priv, _ := newServerWithLinker(t, coachlink.NewClient(identity.server.URL, "interno", 0))

	tenant := uuid.NewString()
	coach, other, student := uuid.NewString(), uuid.NewString(), uuid.NewString()
	tokStudent := signToken(t, priv, tenant, student, []string{"student"})
	tokCoach := signToken(t, priv, tenant, coach, []string{"coach"})

	if status, code, _ := doRaw(t, server, http.MethodPost, "/v1/conversations", tokStudent, nil); status != http.StatusConflict || code != "no_coach" {
		t.Fatalf("aluno sem professor: esperava 409 no_coach, obtive %d %s", status, code)
	}

	identity.assign(student, coach)
	// Tentar escolher outro professor no corpo não muda nada.
	status, _, raw := doRaw(t, server, http.MethodPost, "/v1/conversations", tokStudent, map[string]string{"student_id": other})
	if status != http.StatusOK {
		t.Fatalf("aluno abrindo conversa: esperava 200, obtive %d %s", status, raw)
	}
	var conv struct {
		ID        string `json:"id"`
		StudentID string `json:"student_id"`
		CoachID   string `json:"coach_id"`
	}
	if err := json.Unmarshal(raw, &conv); err != nil {
		t.Fatal(err)
	}
	if conv.StudentID != student || conv.CoachID != coach {
		t.Fatalf("conversa com os participantes errados: %+v", conv)
	}

	// O coach recupera a mesma conversa (GetOrCreate idempotente).
	_, _, raw = doRaw(t, server, http.MethodPost, "/v1/conversations", tokCoach, map[string]string{"student_id": student})
	var again struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(raw, &again)
	if again.ID != conv.ID {
		t.Fatalf("coach deveria recuperar a conversa %s, obteve %s", conv.ID, again.ID)
	}

	identity.setDown(true)
	if status, _, _ := doRaw(t, server, http.MethodPost, "/v1/conversations", tokStudent, nil); status != http.StatusInternalServerError {
		t.Fatalf("identity fora: esperava 500, obtive %d", status)
	}
}
