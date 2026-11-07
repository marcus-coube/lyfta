package ratelimit

import (
	"context"
	"testing"
	"time"
)

func TestMemoryStoreCooldown(t *testing.T) {
	ctx := context.Background()
	s := NewMemoryStore()
	now := time.Date(2026, 11, 7, 10, 0, 0, 0, time.UTC)
	s.SetClock(func() time.Time { return now })

	const limit = 3
	const ttl = 5 * time.Minute

	for i := 1; i < limit; i++ {
		if n, _ := s.Hit(ctx, "k", limit, ttl); n != i {
			t.Fatalf("hit %d: contador %d", i, n)
		}
		if _, blocked, _ := s.Blocked(ctx, "k", limit); blocked {
			t.Fatalf("bloqueou antes do limite (hit %d)", i)
		}
		now = now.Add(time.Minute)
	}

	// O hit que atinge o limite reinicia a janela: bloqueio de ttl inteiro.
	s.Hit(ctx, "k", limit, ttl)
	retry, blocked, _ := s.Blocked(ctx, "k", limit)
	if !blocked || retry != ttl {
		t.Fatalf("esperava bloqueio de %v, obtive blocked=%v retry=%v", ttl, blocked, retry)
	}

	// Hits durante o bloqueio não estendem o cooldown.
	now = now.Add(4 * time.Minute)
	s.Hit(ctx, "k", limit, ttl)
	if retry, blocked, _ := s.Blocked(ctx, "k", limit); !blocked || retry != time.Minute {
		t.Fatalf("esperava 1min restante, obtive blocked=%v retry=%v", blocked, retry)
	}

	now = now.Add(time.Minute)
	if _, blocked, _ := s.Blocked(ctx, "k", limit); blocked {
		t.Fatal("deveria liberar depois do cooldown")
	}
}

func TestMemoryStoreWindowExpires(t *testing.T) {
	ctx := context.Background()
	s := NewMemoryStore()
	now := time.Date(2026, 11, 7, 10, 0, 0, 0, time.UTC)
	s.SetClock(func() time.Time { return now })

	s.Hit(ctx, "k", 3, 5*time.Minute)
	s.Hit(ctx, "k", 3, 5*time.Minute)
	now = now.Add(5 * time.Minute)
	// Janela expirou: o contador recomeça.
	if n, _ := s.Hit(ctx, "k", 3, 5*time.Minute); n != 1 {
		t.Fatalf("esperava contador reiniciado, obtive %d", n)
	}
}

func TestMemoryStoreReset(t *testing.T) {
	ctx := context.Background()
	s := NewMemoryStore()
	for i := 0; i < 3; i++ {
		s.Hit(ctx, "k", 3, time.Minute)
	}
	_ = s.Reset(ctx, "k")
	if _, blocked, _ := s.Blocked(ctx, "k", 3); blocked {
		t.Fatal("reset deveria liberar a chave")
	}
}
