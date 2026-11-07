package http

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"math"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/marcus-coube/lyfta/identity/internal/ratelimit"
)

// RateLimitCooldown é a janela de contagem e o tempo de bloqueio depois que
// uma chave atinge o limite (ADR-002 §2c).
const RateLimitCooldown = 5 * time.Minute

// countMode define que respostas contam como tentativa.
type countMode int

const (
	// countAll conta toda requisição (endpoints que disparam e-mail ou criam
	// recurso: o custo é a chamada em si).
	countAll countMode = iota
	// countFailures conta só respostas 4xx (exceto 409 e 429): adivinhação de
	// senha/token. 409 fica de fora porque no login significa senha certa
	// em mais de um tenant.
	countFailures
)

// RateRule é a regra de um endpoint: limites por IP e por e-mail do corpo
// (0 = sem limite naquela dimensão).
type RateRule struct {
	Scope      string
	IPLimit    int
	EmailLimit int
	Mode       countMode
	// ResetEmailOnSuccess zera o contador do e-mail numa resposta 2xx
	// (login certo não deve carregar as falhas anteriores).
	ResetEmailOnSuccess bool
}

// Regras dos endpoints públicos. Os limites por IP são folgados porque uma
// academia inteira pode sair pelo mesmo IP (Wi-Fi da academia, CGNAT).
var (
	ruleLogin          = RateRule{Scope: "login", IPLimit: 30, EmailLimit: 5, Mode: countFailures, ResetEmailOnSuccess: true}
	ruleForgotPassword = RateRule{Scope: "forgot", IPLimit: 10, EmailLimit: 3, Mode: countAll}
	ruleResetPassword  = RateRule{Scope: "reset", IPLimit: 10, Mode: countFailures}
	ruleAcceptInvite   = RateRule{Scope: "accept", IPLimit: 10, Mode: countFailures}
	ruleSignup         = RateRule{Scope: "signup", IPLimit: 10, Mode: countAll}
)

// RateLimiter aplica as RateRule sobre um ratelimit.Store.
type RateLimiter struct {
	store      ratelimit.Store
	logger     *slog.Logger
	trustProxy bool
}

// NewRateLimiter cria o limitador. trustProxy=true usa o último IP do
// X-Forwarded-For (o que o nosso proxy reverso anexou); false usa a conexão.
// Nunca ligar sem proxy na frente: o header seria forjável pelo cliente.
func NewRateLimiter(store ratelimit.Store, logger *slog.Logger, trustProxy bool) *RateLimiter {
	return &RateLimiter{store: store, logger: logger, trustProxy: trustProxy}
}

type rateKey struct {
	key   string
	limit int
}

// maxRateBody limita o quanto o middleware lê do corpo para achar o e-mail.
const maxRateBody = 64 << 10

// middleware devolve o middleware da regra. Responde 429 too_many_requests com
// Retry-After enquanto alguma das chaves estiver bloqueada; depois do
// handler, conta a tentativa conforme o Mode.
func (l *RateLimiter) middleware(rule RateRule) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			var keys []rateKey
			if rule.IPLimit > 0 {
				keys = append(keys, rateKey{"rl:" + rule.Scope + ":ip:" + l.clientIP(r), rule.IPLimit})
			}
			emailKey := ""
			if rule.EmailLimit > 0 {
				if email := peekEmail(r); email != "" {
					// Hash: o e-mail não fica em claro no Redis (ADR-008).
					sum := sha256.Sum256([]byte(email))
					emailKey = "rl:" + rule.Scope + ":email:" + hex.EncodeToString(sum[:16])
					keys = append(keys, rateKey{emailKey, rule.EmailLimit})
				}
			}

			for _, k := range keys {
				retry, blocked, err := l.store.Blocked(ctx, k.key, k.limit)
				if err != nil {
					// Falha aberta: Redis fora não pode derrubar o login.
					l.logger.Error("rate_limit_check_failed", slog.String("scope", rule.Scope), slog.Any("error", err))
					continue
				}
				if blocked {
					writeTooManyRequests(w, retry)
					return
				}
			}

			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rec, r)

			if counts(rule.Mode, rec.status) {
				for _, k := range keys {
					if _, err := l.store.Hit(ctx, k.key, k.limit, RateLimitCooldown); err != nil {
						l.logger.Error("rate_limit_hit_failed", slog.String("scope", rule.Scope), slog.Any("error", err))
					}
				}
			}
			if rule.ResetEmailOnSuccess && emailKey != "" && rec.status >= 200 && rec.status < 300 {
				if err := l.store.Reset(ctx, emailKey); err != nil {
					l.logger.Error("rate_limit_reset_failed", slog.String("scope", rule.Scope), slog.Any("error", err))
				}
			}
		})
	}
}

func counts(mode countMode, status int) bool {
	if mode == countAll {
		return true
	}
	return status >= 400 && status < 500 && status != http.StatusConflict && status != http.StatusTooManyRequests
}

func writeTooManyRequests(w http.ResponseWriter, retry time.Duration) {
	secs := int(math.Ceil(retry.Seconds()))
	if secs < 1 {
		secs = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(secs))
	writeError(w, newAPIError(http.StatusTooManyRequests, "too_many_requests", "retry_after_seconds", secs))
}

// peekEmail lê o campo "email" do corpo JSON e devolve o corpo intacto para
// o handler.
func peekEmail(r *http.Request) string {
	if r.Body == nil {
		return ""
	}
	raw, err := io.ReadAll(io.LimitReader(r.Body, maxRateBody))
	_ = r.Body.Close()
	r.Body = io.NopCloser(bytes.NewReader(raw))
	if err != nil {
		return ""
	}
	var body struct {
		Email string `json:"email"`
	}
	if json.Unmarshal(raw, &body) != nil {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(body.Email))
}

func (l *RateLimiter) clientIP(r *http.Request) string {
	if l.trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
				return ip
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// statusRecorder captura o status escrito pelo handler.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}
