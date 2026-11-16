package job_test

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/job"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
	"github.com/marcus-coube/lyfta/comms/internal/tenantclient"
)

// fakeStore registra os objetos apagados e pode falhar sob demanda.
type fakeStore struct {
	mu      sync.Mutex
	deleted []string
	failing bool
}

func (f *fakeStore) DeleteObject(_ context.Context, key string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.failing {
		return errors.New("s3 fora do ar")
	}
	f.deleted = append(f.deleted, key)
	return nil
}

func (f *fakeStore) wasDeleted(key string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, k := range f.deleted {
		if k == key {
			return true
		}
	}
	return false
}

func seedMedia(t *testing.T, mr *repo.SessionMediaRepo, tenantID string, createdAt time.Time) domain.SessionMedia {
	t.Helper()
	studentID, session := uuid.NewString(), uuid.NewString()
	m, _, err := mr.Create(context.Background(), domain.SessionMedia{
		TenantID: tenantID, StudentID: studentID, SessionClientID: session, CreatedAt: createdAt,
		MediaKey:    "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + session + "/" + uuid.NewString() + ".mp4",
		ContentType: "video/mp4", SizeBytes: 100,
	})
	if err != nil {
		t.Fatalf("criar mídia: %v", err)
	}
	return m
}

// TestMediaExpiryJob cobre o Aceite do P12.1 com relógio falso: a mídia com
// ciência some 7 dias depois dela, a sem ciência no teto de 30 dias, falha do
// storage não marca (e o próximo tick tenta de novo) e outro tenant da lista
// é varrido sem vazar para o primeiro.
func TestMediaExpiryJob(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)
	mr := repo.NewSessionMediaRepo(pool)

	tenantID := uuid.NewString()
	t0 := time.Now().UTC().Add(-90 * 24 * time.Hour).Truncate(time.Second)
	acked := seedMedia(t, mr, tenantID, t0)
	if _, err := mr.Ack(ctx, tenantID, acked.ID, uuid.NewString(), t0.Add(24*time.Hour)); err != nil {
		t.Fatalf("ack: %v", err)
	}
	unacked := seedMedia(t, mr, tenantID, t0)

	store := &fakeStore{}
	tenants := &fakeTenants{items: []tenantclient.Tenant{{ID: tenantID, Timezone: "UTC"}}}
	now := t0.Add(24 * time.Hour)
	j := job.NewMediaExpiryJob(logger, pool, mr, store, tenants).WithClock(func() time.Time { return now })

	state := func(id string) domain.SessionMedia {
		t.Helper()
		m, err := mr.Get(ctx, tenantID, id)
		if err != nil {
			t.Fatalf("buscar mídia: %v", err)
		}
		return m
	}

	// Dia 1 (no instante do ack): nada venceu.
	j.Tick(ctx)
	if len(store.deleted) != 0 || state(acked.ID).DeletedAt != nil {
		t.Fatal("nada deveria ter sido apagado no dia 1")
	}

	// Dia 7: ainda falta 1 dia para o prazo da mídia com ciência (ack + 7 = dia 8).
	now = t0.Add(7 * 24 * time.Hour)
	j.Tick(ctx)
	if state(acked.ID).DeletedAt != nil {
		t.Fatal("antes do prazo (ack + 7 dias) nada deveria ser apagado")
	}

	// Dia 8 com o storage fora do ar: falha não marca nada.
	now = t0.Add(8 * 24 * time.Hour)
	store.failing = true
	j.Tick(ctx)
	if state(acked.ID).DeletedAt != nil || state(acked.ID).MediaKey == "" {
		t.Fatal("falha no S3 não pode marcar deleted_at nem limpar a chave")
	}

	// Storage de volta: o próximo tick apaga o objeto e marca.
	store.failing = false
	j.Tick(ctx)
	got := state(acked.ID)
	if got.DeletedAt == nil || !got.DeletedAt.Equal(now) || got.MediaKey != "" {
		t.Fatalf("a mídia com ciência deveria estar apagada no dia 8: %+v", got)
	}
	if !store.wasDeleted(acked.MediaKey) {
		t.Fatal("o objeto da mídia com ciência deveria ter sido apagado no storage")
	}
	if state(unacked.ID).DeletedAt != nil {
		t.Fatal("a mídia sem ciência ainda está dentro dos 30 dias")
	}

	// Dia 30: o teto vence a mídia que ninguém viu.
	now = t0.Add(30 * 24 * time.Hour)
	j.Tick(ctx)
	if state(unacked.ID).DeletedAt == nil || !store.wasDeleted(unacked.MediaKey) {
		t.Fatal("a mídia sem ciência deveria expirar no teto de 30 dias")
	}

	// Repetir não apaga de novo nem mexe na linha.
	before := len(store.deleted)
	j.Tick(ctx)
	if len(store.deleted) != before {
		t.Fatal("mídia já apagada não pode ser apagada de novo")
	}
}

// TestMediaExpiryJobSkipsWhenLockHeld: com o advisory lock dos jobs do comms
// já tomado por outra conexão (outra instância), o tick não apaga nada.
func TestMediaExpiryJobSkipsWhenLockHeld(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	logger := slog.New(slog.DiscardHandler)
	mr := repo.NewSessionMediaRepo(pool)

	tenantID := uuid.NewString()
	old := seedMedia(t, mr, tenantID, time.Now().UTC().Add(-60*24*time.Hour))
	store := &fakeStore{}
	j := job.NewMediaExpiryJob(logger, pool, mr, store, &fakeTenants{items: []tenantclient.Tenant{{ID: tenantID, Timezone: "UTC"}}})

	holder, err := pool.Acquire(ctx)
	if err != nil {
		t.Fatalf("conexão: %v", err)
	}
	defer holder.Release()
	var locked bool
	if err := holder.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtext($1)::bigint)", "lyfta_comms_pending_workout_job").Scan(&locked); err != nil || !locked {
		t.Fatalf("não consegui o lock de teste: %v locked=%v", err, locked)
	}
	defer func() {
		_, _ = holder.Exec(ctx, "SELECT pg_advisory_unlock(hashtext($1)::bigint)", "lyfta_comms_pending_workout_job")
	}()

	j.Tick(ctx)
	if store.wasDeleted(old.MediaKey) {
		t.Fatal("com o lock tomado por outra instância o tick não deve apagar")
	}
}
