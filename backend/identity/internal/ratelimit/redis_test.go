package ratelimit

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
)

// TestRedisStoreCooldown roda contra o Redis real (docker compose no dev,
// step do CI). Sem REDIS_URL, pula — exceto no CI, onde falhar é o certo.
func TestRedisStoreCooldown(t *testing.T) {
	url := os.Getenv("REDIS_URL")
	if url == "" {
		if os.Getenv("CI") != "" {
			t.Fatal("REDIS_URL vazia no CI")
		}
		t.Skip("REDIS_URL vazia: pulando teste do RedisStore")
	}
	ctx := context.Background()
	s, err := NewRedisStore(ctx, url)
	if err != nil {
		t.Fatalf("conectar no Redis: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })

	key := "rl:test:" + uuid.NewString()
	t.Cleanup(func() { _ = s.Reset(ctx, key) })
	const limit = 3
	const ttl = 5 * time.Minute

	for i := 1; i < limit; i++ {
		if n, err := s.Hit(ctx, key, limit, ttl); err != nil || n != i {
			t.Fatalf("hit %d: contador %d, erro %v", i, n, err)
		}
		if _, blocked, err := s.Blocked(ctx, key, limit); err != nil || blocked {
			t.Fatalf("bloqueou antes do limite (hit %d, erro %v)", i, err)
		}
	}

	s.Hit(ctx, key, limit, ttl)
	retry, blocked, err := s.Blocked(ctx, key, limit)
	if err != nil || !blocked || retry <= ttl-5*time.Second || retry > ttl {
		t.Fatalf("esperava bloqueio de ~%v, obtive blocked=%v retry=%v erro=%v", ttl, blocked, retry, err)
	}

	if err := s.Reset(ctx, key); err != nil {
		t.Fatal(err)
	}
	if _, blocked, _ := s.Blocked(ctx, key, limit); blocked {
		t.Fatal("reset deveria liberar a chave")
	}
}
