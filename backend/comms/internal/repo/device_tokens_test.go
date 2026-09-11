package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// TestDeviceTokenUpsertReplacesTokenAndLocale cobre o Aceite do passo 1 da
// P3.4: reinstalar o app (mesmo user+platform, token novo) faz upsert, não
// cria um segundo registro — e o locale é reescrito junto (o app manda o
// locale corrente a cada registro).
func TestDeviceTokenUpsertReplacesTokenAndLocale(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, userID := newID(), newID()
	tokens := repo.NewDeviceTokenRepo(pool)

	first, err := tokens.Upsert(ctx, tenantID, userID, domain.PlatformAndroid, "tok-1", domain.LocalePTBR)
	if err != nil {
		t.Fatalf("primeiro upsert: %v", err)
	}
	second, err := tokens.Upsert(ctx, tenantID, userID, domain.PlatformAndroid, "tok-2", domain.LocaleEN)
	if err != nil {
		t.Fatalf("segundo upsert: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("upsert deveria manter a mesma linha (tenant+user+platform), veio %s != %s", second.ID, first.ID)
	}
	if second.Token != "tok-2" || second.Locale != domain.LocaleEN {
		t.Fatalf("upsert deveria atualizar token e locale, veio %+v", second)
	}

	list, err := tokens.ListForUser(ctx, tenantID, userID)
	if err != nil {
		t.Fatalf("listar devices: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("esperava 1 device (upsert, não duplicata), veio %d", len(list))
	}
}

// TestDeviceTokenListForUserIsTenantScoped cobre ADR-001 §6: mesmo user_id
// sob dois tenants diferentes não vaza device token de um pro outro — a
// aplicação normalmente nunca teria o mesmo user_id em dois tenants, mas a
// garantia é da policy de RLS, não de uma coincidência de dado.
func TestDeviceTokenListForUserIsTenantScoped(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newID(), newID()
	userID := newID()
	tokens := repo.NewDeviceTokenRepo(pool)

	if _, err := tokens.Upsert(ctx, tenantA, userID, domain.PlatformAndroid, "tok-a", domain.LocalePTBR); err != nil {
		t.Fatalf("upsert no tenant A: %v", err)
	}

	listB, err := tokens.ListForUser(ctx, tenantB, userID)
	if err != nil {
		t.Fatalf("listar no tenant B: %v", err)
	}
	if len(listB) != 0 {
		t.Fatalf("vazamento entre tenants: B enxergou %d device(s) do mesmo user_id em A", len(listB))
	}
}

// TestNotificationLogExistsInRangeDedupe cobre o dedupe do job diário (P3.4):
// um Record dentro do intervalo consultado faz ExistsInRange responder true;
// fora do intervalo (nem antes nem depois), false.
func TestNotificationLogExistsInRangeDedupe(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, userID := newID(), newID()
	logs := repo.NewNotificationLogRepo(pool)

	since := time.Now().Add(-time.Hour)
	until := time.Now().Add(time.Hour)

	before, err := logs.ExistsInRange(ctx, tenantID, userID, "workout_pending", since, until)
	if err != nil {
		t.Fatalf("checar dedupe antes de gravar: %v", err)
	}
	if before {
		t.Fatal("não deveria existir log antes de Record")
	}

	if err := logs.Record(ctx, tenantID, userID, "workout_pending", map[string]any{"title": "x"}); err != nil {
		t.Fatalf("gravar log: %v", err)
	}

	after, err := logs.ExistsInRange(ctx, tenantID, userID, "workout_pending", since, until)
	if err != nil {
		t.Fatalf("checar dedupe depois de gravar: %v", err)
	}
	if !after {
		t.Fatal("deveria existir log dentro do intervalo depois de Record")
	}

	// Fora da janela (o "amanhã" de outro dia) — dedupe não vaza entre dias.
	tomorrowSince := until
	tomorrowUntil := until.Add(24 * time.Hour)
	nextDay, err := logs.ExistsInRange(ctx, tenantID, userID, "workout_pending", tomorrowSince, tomorrowUntil)
	if err != nil {
		t.Fatalf("checar dedupe do dia seguinte: %v", err)
	}
	if nextDay {
		t.Fatal("log de hoje não deveria contar como dedupe do dia seguinte")
	}

	// Outro `kind` não é a mesma notificação — não deve contar.
	otherKind, err := logs.ExistsInRange(ctx, tenantID, userID, "message_new", since, until)
	if err != nil {
		t.Fatalf("checar dedupe de outro kind: %v", err)
	}
	if otherKind {
		t.Fatal("kind diferente não deveria contar para o dedupe")
	}
}
