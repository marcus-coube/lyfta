// Package ratelimit conta tentativas por chave e bloqueia a chave por um
// cooldown quando o limite é atingido — a proteção contra força bruta e
// enumeração dos endpoints públicos do identity (ADR-002 §2c).
//
// Semântica (igual nas duas implementações): cada Hit incrementa o contador
// da chave; o contador vive por `ttl` a partir do primeiro Hit e, no Hit que
// atinge o limite, o ttl recomeça — a chave fica bloqueada por `ttl` inteiro
// a partir daí. Hits durante o bloqueio não o estendem.
package ratelimit

import (
	"context"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// Store guarda os contadores. Redis em produção (vale entre instâncias);
// memória em dev e nos testes.
type Store interface {
	// Hit registra uma tentativa e devolve o contador após o incremento.
	Hit(ctx context.Context, key string, limit int, ttl time.Duration) (int, error)
	// Blocked diz se a chave atingiu o limite e quanto falta para liberar.
	Blocked(ctx context.Context, key string, limit int) (time.Duration, bool, error)
	// Reset zera a chave (ex.: login bem-sucedido limpa as falhas do e-mail).
	Reset(ctx context.Context, key string) error
}

// --- Redis -----------------------------------------------------------------

// hitScript faz INCR + PEXPIRE atomicamente: sem isso, uma queda entre os
// dois comandos deixaria a chave sem TTL, bloqueada para sempre.
var hitScript = redis.NewScript(`
local c = redis.call('INCR', KEYS[1])
if c == 1 or c == tonumber(ARGV[1]) then
  redis.call('PEXPIRE', KEYS[1], ARGV[2])
end
return c
`)

// RedisStore implementa Store no Redis.
type RedisStore struct {
	client *redis.Client
}

// NewRedisStore cria o client a partir da REDIS_URL e confirma a conexão com
// PING — falhar na subida é melhor que descobrir no primeiro login.
func NewRedisStore(ctx context.Context, redisURL string) (*RedisStore, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, err
	}
	client := redis.NewClient(opts)
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, err
	}
	return &RedisStore{client: client}, nil
}

// Close fecha o client Redis.
func (s *RedisStore) Close() error { return s.client.Close() }

func (s *RedisStore) Hit(ctx context.Context, key string, limit int, ttl time.Duration) (int, error) {
	n, err := hitScript.Run(ctx, s.client, []string{key}, limit, ttl.Milliseconds()).Int()
	if err != nil {
		return 0, err
	}
	return n, nil
}

func (s *RedisStore) Blocked(ctx context.Context, key string, limit int) (time.Duration, bool, error) {
	n, err := s.client.Get(ctx, key).Int()
	if err == redis.Nil {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	if n < limit {
		return 0, false, nil
	}
	ttl, err := s.client.PTTL(ctx, key).Result()
	if err != nil {
		return 0, false, err
	}
	if ttl <= 0 {
		return 0, false, nil
	}
	return ttl, true, nil
}

func (s *RedisStore) Reset(ctx context.Context, key string) error {
	return s.client.Del(ctx, key).Err()
}

// --- Memória ---------------------------------------------------------------

type entry struct {
	count   int
	expires time.Time
}

// MemoryStore implementa Store em memória do processo. Só serve para uma
// instância (dev/teste): com N réplicas cada uma teria o seu contador.
type MemoryStore struct {
	mu      sync.Mutex
	entries map[string]entry
	now     func() time.Time
}

// NewMemoryStore cria um MemoryStore vazio.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{entries: map[string]entry{}, now: time.Now}
}

// SetClock troca o relógio (testes de expiração do cooldown).
func (s *MemoryStore) SetClock(now func() time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.now = now
}

func (s *MemoryStore) live(key string) (entry, bool) {
	e, ok := s.entries[key]
	if !ok {
		return entry{}, false
	}
	if !s.now().Before(e.expires) {
		delete(s.entries, key)
		return entry{}, false
	}
	return e, true
}

func (s *MemoryStore) Hit(_ context.Context, key string, limit int, ttl time.Duration) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, _ := s.live(key)
	e.count++
	if e.count == 1 || e.count == limit {
		e.expires = s.now().Add(ttl)
	}
	s.entries[key] = e
	return e.count, nil
}

func (s *MemoryStore) Blocked(_ context.Context, key string, limit int) (time.Duration, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.live(key)
	if !ok || e.count < limit {
		return 0, false, nil
	}
	return e.expires.Sub(s.now()), true, nil
}

func (s *MemoryStore) Reset(_ context.Context, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.entries, key)
	return nil
}
