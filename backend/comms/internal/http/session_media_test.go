package http_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/marcus-coube/duo/comms/internal/domain"
	"github.com/marcus-coube/duo/comms/internal/fcm"
	chttp "github.com/marcus-coube/duo/comms/internal/http"
	"github.com/marcus-coube/duo/comms/internal/media"
	"github.com/marcus-coube/duo/comms/internal/pubsub"
	"github.com/marcus-coube/duo/comms/internal/push"
	"github.com/marcus-coube/duo/comms/internal/repo"
	"github.com/marcus-coube/duo/comms/internal/security"
	"github.com/marcus-coube/duo/comms/internal/ws"
)

// Aceite do P12.1 pela API: sobe o roteador real (Postgres + Redis de dev) com
// um storage fake em memória — o storage de verdade (MinIO) é exercitado em
// internal/media (HEAD, DELETE, pasta do aluno).

// fakeMediaStore é o storage em memória: PUT = put(key), HEAD/DELETE como o S3.
type fakeMediaStore struct {
	mu      sync.Mutex
	objects map[string]media.ObjectInfo
	deleted []string
}

func newFakeMediaStore() *fakeMediaStore {
	return &fakeMediaStore{objects: map[string]media.ObjectInfo{}}
}

func (f *fakeMediaStore) PresignSessionMediaPut(_ context.Context, key, contentType string, sizeBytes int64) (string, time.Time, error) {
	return "http://storage.test/" + key, time.Now().Add(15 * time.Minute), nil
}

func (f *fakeMediaStore) Head(_ context.Context, key string) (media.ObjectInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	info, ok := f.objects[key]
	if !ok {
		return media.ObjectInfo{}, media.ErrObjectNotFound
	}
	return info, nil
}

func (f *fakeMediaStore) SignedReadURL(_ context.Context, key string) (string, error) {
	return "http://storage.test/signed/" + key, nil
}

func (f *fakeMediaStore) DeleteObject(_ context.Context, key string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.objects, key)
	f.deleted = append(f.deleted, key)
	return nil
}

func (f *fakeMediaStore) DeleteStudentObjects(_ context.Context, tenantID, studentID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	prefix := media.StudentSessionMediaPrefix(tenantID, studentID)
	for k := range f.objects {
		if strings.HasPrefix(k, prefix) {
			delete(f.objects, k)
			f.deleted = append(f.deleted, k)
		}
	}
	return nil
}

func (f *fakeMediaStore) put(key, contentType string, size int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.objects[key] = media.ObjectInfo{SizeBytes: size, ContentType: contentType}
}

func (f *fakeMediaStore) has(key string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	_, ok := f.objects[key]
	return ok
}

type recordingPusher struct {
	mu   sync.Mutex
	sent []fcm.Message
}

func (p *recordingPusher) Send(_ context.Context, msg fcm.Message) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.sent = append(p.sent, msg)
	return nil
}

func (p *recordingPusher) all() []fcm.Message {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]fcm.Message(nil), p.sent...)
}

type mediaEnv struct {
	server  *httptest.Server
	priv    ed25519.PrivateKey
	hub     *ws.Hub
	store   *fakeMediaStore
	linker  *fakeLinker
	pusher  *recordingPusher
	tokens  *repo.DeviceTokenRepo
	media   *repo.SessionMediaRepo
	erasure *repo.ErasureRepo
}

func newMediaEnv(t *testing.T) *mediaEnv {
	t.Helper()
	pool := testChatPool(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	redisClient, err := pubsub.NewClient(ctx, testChatRedisURL(t))
	if err != nil {
		chatSkipOrFail(t, "Redis indisponível para teste de integração: "+err.Error())
		return nil
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

	linker := newFakeLinker()
	store := newFakeMediaStore()
	pusher := &recordingPusher{}
	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)
	checkins := repo.NewCheckinRepo(pool)
	tokens := repo.NewDeviceTokenRepo(pool)
	notifier := push.NewNotifier(logger, tokens, repo.NewNotificationLogRepo(pool), pusher)
	sessionMedia := repo.NewSessionMediaRepo(pool)
	erasure := repo.NewErasureRepo(pool)

	conversationHandler := chttp.NewConversationHandler(logger, conversations, messages, nil, redisClient, nil, linker)
	mediaHandler := chttp.NewMediaHandler(logger, conversations, nil, linker)
	checkinHandler := chttp.NewCheckinHandler(logger, checkins, linker, redisClient, nil).WithSessionMedia(sessionMedia)
	sessionMediaHandler := chttp.NewSessionMediaHandler(logger, sessionMedia, store, linker, conversations, conversationHandler, notifier)
	router := chttp.NewRouter(logger, []string{"*"}, verifier, "token-m2m", conversationHandler, mediaHandler,
		chttp.NewWSHandler(logger, verifier, hub, redisClient), checkinHandler, nil,
		chttp.NewErasureHandler(logger, erasure, store), sessionMediaHandler)
	server := httptest.NewServer(router)
	t.Cleanup(server.Close)
	return &mediaEnv{server: server, priv: priv, hub: hub, store: store, linker: linker, pusher: pusher,
		tokens: tokens, media: sessionMedia, erasure: erasure}
}

func signTokenWithConsents(t *testing.T, priv ed25519.PrivateKey, tenantID, subject string, roles, consents []string) string {
	t.Helper()
	claims := security.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute)),
		},
		TenantID: tenantID, Roles: roles, Locale: "pt-BR", Consents: consents,
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims).SignedString(priv)
	if err != nil {
		t.Fatalf("assinar token: %v", err)
	}
	return signed
}

// call devolve status e corpo sem falhar o teste (os casos de erro são o
// resultado esperado).
func (e *mediaEnv) call(t *testing.T, method, path, token string, body any) (int, []byte) {
	t.Helper()
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("serializar corpo: %v", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, e.server.URL+path, reader)
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
	out, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, out
}

func (e *mediaEnv) mustCall(t *testing.T, want int, method, path, token string, body any, out any) {
	t.Helper()
	status, raw := e.call(t, method, path, token, body)
	if status != want {
		t.Fatalf("%s %s: esperava %d, veio %d: %s", method, path, want, status, raw)
	}
	if out != nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("decodificar %s %s: %v — %s", method, path, err, raw)
		}
	}
}

func errCode(t *testing.T, raw []byte) string {
	t.Helper()
	var e struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(raw, &e); err != nil {
		t.Fatalf("corpo de erro inválido: %v — %s", err, raw)
	}
	return e.Code
}

type mediaItem struct {
	ID              string     `json:"id"`
	StudentID       string     `json:"student_id"`
	SessionClientID string     `json:"session_client_id"`
	ExerciseName    string     `json:"exercise_name"`
	ContentType     string     `json:"content_type"`
	SizeBytes       int64      `json:"size_bytes"`
	Note            string     `json:"note"`
	CreatedAt       time.Time  `json:"created_at"`
	AckedBy         string     `json:"acked_by"`
	AckedAt         *time.Time `json:"acked_at"`
	DeleteAfter     time.Time  `json:"delete_after"`
	MediaURL        string     `json:"media_url"`
}

type mediaList struct {
	Items      []mediaItem `json:"items"`
	NextCursor string      `json:"next_cursor"`
}

// attach faz presign + "upload" no fake + registro, como o app.
func (e *mediaEnv) attach(t *testing.T, token, session string, extra map[string]any) mediaItem {
	t.Helper()
	var ps struct {
		Key string `json:"key"`
	}
	e.mustCall(t, 200, http.MethodPost, "/v1/me/session-media/presign", token,
		map[string]any{"session_client_id": session, "content_type": "video/mp4", "size_bytes": 5 << 20}, &ps)
	e.store.put(ps.Key, "video/mp4", 5<<20)
	body := map[string]any{"session_client_id": session, "media_key": ps.Key}
	for k, v := range extra {
		body[k] = v
	}
	var item mediaItem
	e.mustCall(t, 201, http.MethodPost, "/v1/me/session-media", token, body, &item)
	return item
}

var photoConsent = []string{"terms", "progress_photos"}

func TestSessionMediaPresignLimitsAndConsent(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID, session := uuid.NewString(), uuid.NewString(), uuid.NewString()
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)

	// 21 MB = 422 (o teto é 20 MB).
	status, raw := e.call(t, http.MethodPost, "/v1/me/session-media/presign", student,
		map[string]any{"session_client_id": session, "content_type": "video/mp4", "size_bytes": 21 << 20})
	if status != http.StatusUnprocessableEntity || errCode(t, raw) != "file_too_large" {
		t.Fatalf("21 MB deveria ser 422 file_too_large, veio %d %s", status, raw)
	}
	status, _ = e.call(t, http.MethodPost, "/v1/me/session-media/presign", student,
		map[string]any{"session_client_id": session, "content_type": "application/pdf", "size_bytes": 10})
	if status != http.StatusUnprocessableEntity {
		t.Fatalf("tipo fora da whitelist deveria ser 422, veio %d", status)
	}
	status, _ = e.call(t, http.MethodPost, "/v1/me/session-media/presign", student,
		map[string]any{"session_client_id": "nao-uuid", "content_type": "video/mp4", "size_bytes": 10})
	if status != http.StatusBadRequest {
		t.Fatalf("session_client_id inválido deveria ser 400, veio %d", status)
	}

	// 20 MB exatos passam e a chave tem o layout do ADR-020.
	var ps struct {
		Key       string            `json:"key"`
		UploadURL string            `json:"upload_url"`
		Method    string            `json:"upload_method"`
		Headers   map[string]string `json:"required_headers"`
	}
	e.mustCall(t, 200, http.MethodPost, "/v1/me/session-media/presign", student,
		map[string]any{"session_client_id": session, "content_type": "video/quicktime", "size_bytes": 20 << 20}, &ps)
	prefix := "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + session + "/"
	if !strings.HasPrefix(ps.Key, prefix) || !strings.HasSuffix(ps.Key, ".mov") || ps.Method != "PUT" || ps.UploadURL == "" {
		t.Fatalf("presign inesperado: %+v", ps)
	}

	// Sem a finalidade progress_photos (D6): 403 consent_required.
	noConsent := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, []string{"terms"})
	status, raw = e.call(t, http.MethodPost, "/v1/me/session-media/presign", noConsent,
		map[string]any{"session_client_id": session, "content_type": "video/mp4", "size_bytes": 10})
	if status != http.StatusForbidden || errCode(t, raw) != "consent_required" {
		t.Fatalf("sem consentimento deveria ser 403 consent_required, veio %d %s", status, raw)
	}
	status, _ = e.call(t, http.MethodPost, "/v1/me/session-media", noConsent,
		map[string]any{"session_client_id": session, "media_key": ps.Key})
	if status != http.StatusForbidden {
		t.Fatalf("registro sem consentimento deveria ser 403, veio %d", status)
	}
}

func TestSessionMediaCreateValidationAndFourthIs422(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID, session := uuid.NewString(), uuid.NewString(), uuid.NewString()
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)

	// Chave fora da pasta da sessão do aluno: 422 invalid_media_key.
	foreign := "tenants/" + tenantID + "/students/" + uuid.NewString() + "/session-media/" + session + "/x.mp4"
	e.store.put(foreign, "video/mp4", 100)
	status, raw := e.call(t, http.MethodPost, "/v1/me/session-media", student,
		map[string]any{"session_client_id": session, "media_key": foreign})
	if status != http.StatusUnprocessableEntity || errCode(t, raw) != "invalid_media_key" {
		t.Fatalf("chave de outro aluno deveria ser 422 invalid_media_key, veio %d %s", status, raw)
	}

	// Objeto que nunca subiu: 422 media_not_uploaded.
	ghost := "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + session + "/ghost.mp4"
	status, raw = e.call(t, http.MethodPost, "/v1/me/session-media", student,
		map[string]any{"session_client_id": session, "media_key": ghost})
	if status != http.StatusUnprocessableEntity || errCode(t, raw) != "media_not_uploaded" {
		t.Fatalf("sem objeto deveria ser 422 media_not_uploaded, veio %d %s", status, raw)
	}

	// Objeto acima do limite (o cliente mentiu no presign): recusado e apagado.
	big := "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + session + "/big.mp4"
	e.store.put(big, "video/mp4", 21<<20)
	status, raw = e.call(t, http.MethodPost, "/v1/me/session-media", student,
		map[string]any{"session_client_id": session, "media_key": big})
	if status != http.StatusUnprocessableEntity || errCode(t, raw) != "file_too_large" || e.store.has(big) {
		t.Fatalf("objeto de 21 MB deveria ser 422 e apagado do storage, veio %d %s (existe=%v)", status, raw, e.store.has(big))
	}

	// Observação acima de 280: 400.
	long := "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + session + "/long.mp4"
	e.store.put(long, "video/mp4", 100)
	status, _ = e.call(t, http.MethodPost, "/v1/me/session-media", student,
		map[string]any{"session_client_id": session, "media_key": long, "note": strings.Repeat("a", 281)})
	if status != http.StatusBadRequest {
		t.Fatalf("nota de 281 caracteres deveria ser 400, veio %d", status)
	}

	// Três mídias passam (tamanho e tipo vêm do HEAD), a 4ª é 422.
	first := e.attach(t, student, session, map[string]any{"exercise_name": "Supino", "note": "ombro travou"})
	if first.SizeBytes != 5<<20 || first.ContentType != "video/mp4" || first.ExerciseName != "Supino" || first.MediaURL == "" {
		t.Fatalf("mídia registrada inesperada: %+v", first)
	}
	if got := first.DeleteAfter.Sub(first.CreatedAt); got != 30*24*time.Hour {
		t.Fatalf("delete_after deveria ser +30 dias, foi +%s", got)
	}
	e.attach(t, student, session, nil)
	e.attach(t, student, session, nil)

	var ps struct {
		Key string `json:"key"`
	}
	e.mustCall(t, 200, http.MethodPost, "/v1/me/session-media/presign", student,
		map[string]any{"session_client_id": session, "content_type": "image/jpeg", "size_bytes": 100}, &ps)
	e.store.put(ps.Key, "image/jpeg", 100)
	status, raw = e.call(t, http.MethodPost, "/v1/me/session-media", student,
		map[string]any{"session_client_id": session, "media_key": ps.Key})
	if status != http.StatusUnprocessableEntity || errCode(t, raw) != "session_media_limit" {
		t.Fatalf("a 4ª mídia deveria ser 422 session_media_limit, veio %d %s", status, raw)
	}
	if e.store.has(ps.Key) {
		t.Fatal("o objeto recusado pelo limite deveria ser apagado do storage")
	}

	// A lista da sessão devolve as três.
	var list mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/me/session-media?session_client_id="+session, student, nil, &list)
	if len(list.Items) != 3 {
		t.Fatalf("esperava 3 mídias na sessão, vieram %d", len(list.Items))
	}
}

func TestSessionMediaAckFeedbackAndStats(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID, coachID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	e.linker.link(coachID, studentID)
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)
	coach := signTokenWithConsents(t, e.priv, tenantID, coachID, []string{"coach"}, nil)

	// O coach tem device registrado: a mídia nova chega como push.
	if _, err := e.tokens.Upsert(context.Background(), tenantID, coachID, domain.PlatformAndroid, "tok-"+uuid.NewString(), domain.LocalePTBR); err != nil {
		t.Fatalf("device do coach: %v", err)
	}

	session := uuid.NewString()
	item := e.attach(t, student, session, map[string]any{"exercise_name": "Agachamento"})

	var pushed []fcm.Message
	for i := 0; i < 50 && len(pushed) == 0; i++ {
		pushed = e.pusher.all()
		time.Sleep(10 * time.Millisecond)
	}
	if len(pushed) != 1 || pushed[0].Data["type"] != "session_media.new" || pushed[0].Data["student_id"] != studentID || pushed[0].Data["tab"] != "checkins" {
		t.Fatalf("o coach deveria receber 1 push de mídia nova, veio %+v", pushed)
	}

	// Stats: 1 mídia sem ciência; aparece em "Para avaliar" (pending=true).
	var stats struct {
		Unreviewed   int `json:"unreviewed"`
		UnackedMedia int `json:"unacked_media"`
	}
	e.mustCall(t, 200, http.MethodGet, "/v1/checkins/stats", coach, nil, &stats)
	if stats.UnackedMedia != 1 {
		t.Fatalf("unacked_media deveria ser 1, veio %+v", stats)
	}
	var pending mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media?student_id="+studentID+"&pending=true", coach, nil, &pending)
	if len(pending.Items) != 1 || pending.Items[0].ID != item.ID || pending.Items[0].MediaURL == "" {
		t.Fatalf("pending deveria trazer a mídia com URL de leitura: %+v", pending)
	}
	// Sem student_id: o coach vê a dos alunos dele.
	var mine mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media?pending=true", coach, nil, &mine)
	if len(mine.Items) != 1 {
		t.Fatalf("a lista do coach deveria ter a mídia do aluno dele: %+v", mine)
	}

	// O aluno conecta no WS: a resposta chega como message.new.
	studentConn := dialWS(t, e.server, student)
	waitOnline(t, e.hub, studentID)

	var acked mediaItem
	e.mustCall(t, 200, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", coach,
		map[string]any{"feedback": "Desce mais o quadril."}, &acked)
	if acked.AckedBy != coachID || acked.AckedAt == nil {
		t.Fatalf("ciência não gravada: %+v", acked)
	}
	if want := acked.AckedAt.Add(7 * 24 * time.Hour); !acked.DeleteAfter.Equal(want) {
		t.Fatalf("delete_after deveria ser ack + 7 dias (%s), foi %s", want, acked.DeleteAfter)
	}

	ev := readWSEvent(t, studentConn)
	if ev.Type != "message.new" || ev.Message == nil || ev.Message.SenderID != coachID ||
		!strings.Contains(ev.Message.Body, "Desce mais o quadril.") || !strings.Contains(ev.Message.Body, "Agachamento") {
		t.Fatalf("o feedback deveria chegar ao aluno como message.new citando o exercício: %+v", ev)
	}

	// O mesmo texto está no histórico do chat do aluno (a conversa foi criada).
	var convs conversationListEnvelope
	e.mustCall(t, 200, http.MethodGet, "/v1/conversations", student, nil, &convs)
	if len(convs.Items) != 1 || convs.Items[0].CoachID != coachID {
		t.Fatalf("o aluno deveria ter a conversa com o coach: %+v", convs)
	}
	var history messageListEnvelope
	e.mustCall(t, 200, http.MethodGet, "/v1/conversations/"+convs.Items[0].ID+"/messages", student, nil, &history)
	if len(history.Items) != 1 || !strings.Contains(history.Items[0].Body, "Desce mais o quadril.") {
		t.Fatalf("histórico do chat inesperado: %+v", history)
	}

	// Segundo ack (agora sem feedback): nada muda, o prazo não renova.
	var second mediaItem
	e.mustCall(t, 200, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", coach, nil, &second)
	if !second.AckedAt.Equal(*acked.AckedAt) || !second.DeleteAfter.Equal(acked.DeleteAfter) || second.AckedBy != coachID {
		t.Fatalf("o segundo ack não pode mudar a ciência nem o prazo: %+v vs %+v", second, acked)
	}
	e.mustCall(t, 200, http.MethodGet, "/v1/checkins/stats", coach, nil, &stats)
	if stats.UnackedMedia != 0 {
		t.Fatalf("depois da ciência unacked_media deveria ser 0, veio %+v", stats)
	}
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media?student_id="+studentID+"&pending=true", coach, nil, &pending)
	if len(pending.Items) != 0 {
		t.Fatalf("pending deveria esvaziar depois da ciência: %+v", pending)
	}
	// O aluno vê o estado "visto" na lista da sessão.
	var own mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/me/session-media?session_client_id="+session, student, nil, &own)
	if len(own.Items) != 1 || own.Items[0].AckedAt == nil {
		t.Fatalf("o aluno deveria ver a ciência: %+v", own)
	}
}

func TestSessionMediaCoachOutsideLinkIs404(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID, coachID, strangerID := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	e.linker.link(coachID, studentID)
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)
	stranger := signTokenWithConsents(t, e.priv, tenantID, strangerID, []string{"coach"}, nil)
	owner := signTokenWithConsents(t, e.priv, tenantID, uuid.NewString(), []string{"owner"}, nil)
	item := e.attach(t, student, uuid.NewString(), nil)

	status, raw := e.call(t, http.MethodGet, "/v1/session-media?student_id="+studentID, stranger, nil)
	if status != http.StatusNotFound || errCode(t, raw) != "student_not_found" {
		t.Fatalf("listar aluno de outro coach deveria ser 404 student_not_found, veio %d %s", status, raw)
	}
	status, raw = e.call(t, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", stranger, nil)
	if status != http.StatusNotFound {
		t.Fatalf("ack fora do vínculo deveria ser 404, veio %d %s", status, raw)
	}
	// Sem student_id o estranho só enxerga os alunos dele (nenhum).
	var list mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media", stranger, nil, &list)
	if len(list.Items) != 0 {
		t.Fatalf("o coach sem alunos não pode ver mídia alheia: %+v", list)
	}
	// O ack falho não gravou nada; o owner pode dar ciência.
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media?student_id="+studentID+"&pending=true", owner, nil, &list)
	if len(list.Items) != 1 {
		t.Fatalf("a mídia deveria seguir sem ciência: %+v", list)
	}
	var acked mediaItem
	e.mustCall(t, 200, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", owner, nil, &acked)
	if acked.AckedAt == nil {
		t.Fatal("o owner pode dar ciência")
	}
	// O aluno não usa as rotas do professor.
	if status, _ := e.call(t, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", student, nil); status != http.StatusForbidden {
		t.Fatalf("aluno dando ciência deveria ser 403, veio %d", status)
	}
}

func TestSessionMediaCrossTenantIsolation(t *testing.T) {
	e := newMediaEnv(t)
	tenantA, tenantB := uuid.NewString(), uuid.NewString()
	studentID, coachB := uuid.NewString(), uuid.NewString()
	student := signTokenWithConsents(t, e.priv, tenantA, studentID, []string{"student"}, photoConsent)
	item := e.attach(t, student, uuid.NewString(), nil)

	// Um owner do tenant B (vê o tenant inteiro dele) não enxerga nem age no A.
	ownerB := signTokenWithConsents(t, e.priv, tenantB, coachB, []string{"owner"}, nil)
	var list mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media", ownerB, nil, &list)
	if len(list.Items) != 0 {
		t.Fatalf("outro tenant não pode listar a mídia: %+v", list)
	}
	e.mustCall(t, 200, http.MethodGet, "/v1/session-media?student_id="+studentID, ownerB, nil, &list)
	if len(list.Items) != 0 {
		t.Fatalf("outro tenant não pode listar a mídia do aluno: %+v", list)
	}
	if status, _ := e.call(t, http.MethodPost, "/v1/session-media/"+item.ID+"/ack", ownerB, nil); status != http.StatusNotFound {
		t.Fatalf("ack cross-tenant deveria ser 404, veio %d", status)
	}
	// O mesmo UUID de aluno no tenant B tampouco retira a mídia do A.
	sameIDinB := signTokenWithConsents(t, e.priv, tenantB, studentID, []string{"student"}, photoConsent)
	if status, _ := e.call(t, http.MethodDelete, "/v1/me/session-media/"+item.ID, sameIDinB, nil); status != http.StatusNotFound {
		t.Fatalf("retirada cross-tenant deveria ser 404, veio %d", status)
	}
	var stats struct {
		UnackedMedia int `json:"unacked_media"`
	}
	e.mustCall(t, 200, http.MethodGet, "/v1/checkins/stats", ownerB, nil, &stats)
	if stats.UnackedMedia != 0 {
		t.Fatalf("o contador do tenant B não pode contar a mídia do A: %+v", stats)
	}
}

func TestSessionMediaStudentCanWithdraw(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID := uuid.NewString(), uuid.NewString()
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)
	other := signTokenWithConsents(t, e.priv, tenantID, uuid.NewString(), []string{"student"}, photoConsent)
	session := uuid.NewString()
	item := e.attach(t, student, session, nil)
	var key string
	for k := range e.store.objects {
		if strings.Contains(k, studentID) {
			key = k
		}
	}

	// Outro aluno do mesmo tenant não retira a mídia alheia.
	if status, _ := e.call(t, http.MethodDelete, "/v1/me/session-media/"+item.ID, other, nil); status != http.StatusNotFound {
		t.Fatalf("retirar mídia de outro aluno deveria ser 404, veio %d", status)
	}
	if !e.store.has(key) {
		t.Fatal("a tentativa alheia não pode apagar o objeto")
	}

	if status, raw := e.call(t, http.MethodDelete, "/v1/me/session-media/"+item.ID, student, nil); status != http.StatusNoContent {
		t.Fatalf("retirar a própria mídia deveria ser 204, veio %d %s", status, raw)
	}
	if e.store.has(key) {
		t.Fatal("o objeto deveria ser apagado na hora")
	}
	var list mediaList
	e.mustCall(t, 200, http.MethodGet, "/v1/me/session-media?session_client_id="+session, student, nil, &list)
	if len(list.Items) != 0 {
		t.Fatalf("a mídia retirada não pode mais aparecer: %+v", list)
	}
}

// TestEraseUserRemovesSessionMediaObjects cobre o Aceite: a exclusão de conta
// (M2M do identity) apaga os objetos do aluno no storage e as linhas.
func TestEraseUserRemovesSessionMediaObjects(t *testing.T) {
	e := newMediaEnv(t)
	tenantID, studentID, other := uuid.NewString(), uuid.NewString(), uuid.NewString()
	student := signTokenWithConsents(t, e.priv, tenantID, studentID, []string{"student"}, photoConsent)
	otherStudent := signTokenWithConsents(t, e.priv, tenantID, other, []string{"student"}, photoConsent)
	session := uuid.NewString()
	e.attach(t, student, session, nil)
	e.attach(t, student, session, nil)
	keep := e.attach(t, otherStudent, uuid.NewString(), nil)

	req, _ := http.NewRequest(http.MethodDelete, e.server.URL+"/internal/v1/users/"+studentID+"?tenant_id="+tenantID, nil)
	req.Header.Set("X-Internal-Token", "token-m2m")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("excluir: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("esperava 204, veio %d", resp.StatusCode)
	}

	for k := range e.store.objects {
		if strings.Contains(k, "/students/"+studentID+"/") {
			t.Fatalf("o objeto %s deveria ter sido apagado", k)
		}
	}
	if len(e.store.objects) != 1 {
		t.Fatalf("o objeto do outro aluno deveria permanecer: %v", e.store.objects)
	}
	if _, err := e.media.Get(context.Background(), tenantID, keep.ID); err != nil {
		t.Fatalf("a linha do outro aluno deveria permanecer: %v", err)
	}
	items, _, err := e.media.List(context.Background(), tenantID, repo.SessionMediaFilter{StudentID: studentID}, nil, "", 0)
	if err != nil || len(items) != 0 {
		t.Fatalf("as linhas do aluno excluído deveriam sumir: %d err=%v", len(items), err)
	}
}
