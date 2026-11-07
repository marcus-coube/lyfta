package repo_test

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// TestEraseUserAnonymizesMessagesAndCheckins cobre a exclusão de conta
// (ADR-008 §2, P4.5): mensagens e check-ins ficam sem autor, os textos livres
// do check-in somem, devices e log de push são excluídos — e o outro
// participante da conversa, o mesmo UUID em outro tenant e a repetição da
// chamada não mudam nada.
func TestEraseUserAnonymizesMessagesAndCheckins(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, otherTenant := newID(), newID()
	studentID, coachID := newID(), newID()

	convID, err := insertConversation(ctx, pool, tenantID, studentID, coachID)
	if err != nil {
		t.Fatalf("conversa: %v", err)
	}
	for _, sender := range []string{studentID, studentID, coachID} {
		if err := insertMessage(ctx, pool, tenantID, convID, sender); err != nil {
			t.Fatalf("mensagem: %v", err)
		}
	}
	if err := insertWorkoutCheckin(ctx, pool, tenantID, studentID); err != nil {
		t.Fatalf("check-in: %v", err)
	}
	if err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE workout_checkins SET pain_notes = 'joelho', comment = 'doeu' WHERE student_id = $1`, studentID)
		return err
	}); err != nil {
		t.Fatalf("textos do check-in: %v", err)
	}
	if err := insertDeviceToken(ctx, pool, tenantID, studentID); err != nil {
		t.Fatalf("device: %v", err)
	}
	if err := insertNotificationLog(ctx, pool, tenantID, studentID); err != nil {
		t.Fatalf("log: %v", err)
	}
	// Mesmo UUID em outro tenant: o RLS impede que a exclusão alcance.
	if err := insertDeviceToken(ctx, pool, otherTenant, studentID); err != nil {
		t.Fatalf("device em outro tenant: %v", err)
	}

	erasure := repo.NewErasureRepo(pool)
	for i := 0; i < 2; i++ { // idempotente
		if err := erasure.EraseUser(ctx, tenantID, studentID); err != nil {
			t.Fatalf("excluir (%d): %v", i+1, err)
		}
	}

	count := func(tenant, q string, args ...any) int {
		t.Helper()
		var n int
		if err := repo.WithTenant(ctx, pool, tenant, func(tx pgx.Tx) error {
			return tx.QueryRow(ctx, q, args...).Scan(&n)
		}); err != nil {
			t.Fatalf("contar: %v", err)
		}
		return n
	}
	if n := count(tenantID, `SELECT count(*) FROM messages WHERE sender_id = $1`, studentID); n != 0 {
		t.Fatalf("o aluno ainda é autor de %d mensagens", n)
	}
	if n := count(tenantID, `SELECT count(*) FROM messages WHERE sender_id = $1`, repo.AnonymousUserID); n != 2 {
		t.Fatalf("esperava 2 mensagens anônimas, há %d", n)
	}
	if n := count(tenantID, `SELECT count(*) FROM messages WHERE sender_id = $1`, coachID); n != 1 {
		t.Fatalf("a mensagem do coach não pode mudar, há %d", n)
	}
	if n := count(tenantID, `SELECT count(*) FROM workout_checkins WHERE student_id = $1 AND pain_notes IS NULL AND comment IS NULL`, repo.AnonymousUserID); n != 1 {
		t.Fatalf("o check-in deveria estar anônimo e sem textos livres, há %d", n)
	}
	if n := count(tenantID, `SELECT count(*) FROM device_tokens WHERE user_id = $1`, studentID); n != 0 {
		t.Fatalf("o device do aluno deveria ter sido excluído, há %d", n)
	}
	if n := count(tenantID, `SELECT count(*) FROM notification_log WHERE user_id = $1`, studentID); n != 0 {
		t.Fatalf("o log de notificação deveria ter sido excluído, há %d", n)
	}
	if n := count(otherTenant, `SELECT count(*) FROM device_tokens WHERE user_id = $1`, studentID); n != 1 {
		t.Fatalf("o device do outro tenant não pode ser tocado, há %d", n)
	}
}
