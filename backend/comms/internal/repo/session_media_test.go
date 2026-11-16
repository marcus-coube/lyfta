package repo_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/duo/comms/internal/domain"
	"github.com/marcus-coube/duo/comms/internal/repo"
)

func newSessionMedia(tenantID, studentID, sessionClientID string) domain.SessionMedia {
	return domain.SessionMedia{
		TenantID: tenantID, StudentID: studentID, SessionClientID: sessionClientID,
		MediaKey:    "tenants/" + tenantID + "/students/" + studentID + "/session-media/" + sessionClientID + "/" + uuid.NewString() + ".mp4",
		ContentType: "video/mp4", SizeBytes: 1024,
	}
}

// TestSessionMediaCreateSetsThirtyDayCeilingAndLimit cobre o passo 1 do P12.1:
// delete_after nasce em created_at + 30 dias (D5), a chave repetida devolve a
// linha existente e a 4ª mídia da sessão é recusada.
func TestSessionMediaCreateSetsThirtyDayCeilingAndLimit(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, session := newID(), newID(), uuid.NewString()
	mr := repo.NewSessionMediaRepo(pool)

	first := newSessionMedia(tenantID, studentID, session)
	created, isNew, err := mr.Create(ctx, first)
	if err != nil || !isNew {
		t.Fatalf("primeira mídia: new=%v err=%v", isNew, err)
	}
	if got := created.DeleteAfter.Sub(created.CreatedAt); got != 30*24*time.Hour {
		t.Fatalf("delete_after deveria ser created_at + 30 dias, foi +%s", got)
	}

	again, isNew, err := mr.Create(ctx, first)
	if err != nil || isNew || again.ID != created.ID {
		t.Fatalf("mesma chave deveria devolver a linha existente: new=%v id=%s err=%v", isNew, again.ID, err)
	}

	for i := 0; i < 2; i++ {
		if _, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, session)); err != nil {
			t.Fatalf("mídia %d: %v", i+2, err)
		}
	}
	if _, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, session)); !errors.Is(err, repo.ErrSessionMediaLimit) {
		t.Fatalf("a 4ª mídia da sessão deveria ser recusada, veio %v", err)
	}
	// Outra sessão do mesmo aluno não é afetada.
	if _, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, uuid.NewString())); err != nil {
		t.Fatalf("outra sessão: %v", err)
	}
}

// TestSessionMediaAck cobre o Aceite: o ack define delete_after em +7 dias, o
// segundo ack não muda nada, e o teto de 30 dias nunca é estendido.
func TestSessionMediaAck(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID := newID(), newID(), newID()
	mr := repo.NewSessionMediaRepo(pool)

	m, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, uuid.NewString()))
	if err != nil {
		t.Fatalf("criar: %v", err)
	}

	ackAt := m.CreatedAt.Add(24 * time.Hour)
	acked, err := mr.Ack(ctx, tenantID, m.ID, coachID, ackAt)
	if err != nil {
		t.Fatalf("ack: %v", err)
	}
	if acked.AckedBy != coachID || acked.AckedAt == nil || !acked.AckedAt.Equal(ackAt) {
		t.Fatalf("ciência não gravada: %+v", acked)
	}
	if want := ackAt.Add(7 * 24 * time.Hour); !acked.DeleteAfter.Equal(want) {
		t.Fatalf("delete_after deveria ser ack + 7 dias (%s), foi %s", want, acked.DeleteAfter)
	}

	second, err := mr.Ack(ctx, tenantID, m.ID, newID(), ackAt.Add(48*time.Hour))
	if err != nil {
		t.Fatalf("segundo ack: %v", err)
	}
	if second.AckedBy != coachID || !second.AckedAt.Equal(ackAt) || !second.DeleteAfter.Equal(acked.DeleteAfter) {
		t.Fatalf("o segundo ack não pode mudar nada: %+v", second)
	}

	// Ack tardio (dia 29): +7 dias passaria do teto de 30 — LEAST mantém o teto.
	late, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, uuid.NewString()))
	if err != nil {
		t.Fatalf("criar: %v", err)
	}
	got, err := mr.Ack(ctx, tenantID, late.ID, coachID, late.CreatedAt.Add(29*24*time.Hour))
	if err != nil {
		t.Fatalf("ack tardio: %v", err)
	}
	if !got.DeleteAfter.Equal(late.DeleteAfter) {
		t.Fatalf("o ack não pode estender o teto de 30 dias: %s != %s", got.DeleteAfter, late.DeleteAfter)
	}
}

// TestSessionMediaTenantIsolation: outro tenant não lê, não lista, não conta
// e não dá ciência (RLS).
func TestSessionMediaTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB, studentID := newID(), newID(), newID()
	mr := repo.NewSessionMediaRepo(pool)

	m, _, err := mr.Create(ctx, newSessionMedia(tenantA, studentID, uuid.NewString()))
	if err != nil {
		t.Fatalf("criar: %v", err)
	}

	if _, err := mr.Get(ctx, tenantB, m.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("Get em outro tenant deveria ser ErrNotFound, veio %v", err)
	}
	if _, err := mr.Ack(ctx, tenantB, m.ID, newID(), time.Now()); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("Ack em outro tenant deveria ser ErrNotFound, veio %v", err)
	}
	items, _, err := mr.List(ctx, tenantB, repo.SessionMediaFilter{}, nil, "", 0)
	if err != nil || len(items) != 0 {
		t.Fatalf("List em outro tenant deveria vir vazia: %d err=%v", len(items), err)
	}
	if n, err := mr.CountUnacked(ctx, tenantB, nil); err != nil || n != 0 {
		t.Fatalf("CountUnacked em outro tenant deveria ser 0: %d err=%v", n, err)
	}
	if ok, err := mr.Delete(ctx, tenantB, studentID, m.ID); err != nil || ok {
		t.Fatalf("Delete em outro tenant não pode apagar: ok=%v err=%v", ok, err)
	}
	if _, err := mr.Get(ctx, tenantA, m.ID); err != nil {
		t.Fatalf("a linha do tenant A deveria estar intacta: %v", err)
	}
	if due, err := mr.ListDue(ctx, tenantB, time.Now().Add(365*24*time.Hour), 10); err != nil || len(due) != 0 {
		t.Fatalf("ListDue em outro tenant deveria vir vazia: %d err=%v", len(due), err)
	}
}

// TestEraseUserRemovesSessionMedia: a exclusão de conta apaga as linhas de
// mídia do aluno e anonimiza quem deu ciência; outro tenant fica intacto.
func TestEraseUserRemovesSessionMedia(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, otherTenant, studentID, coachID := newID(), newID(), newID(), newID()
	mr := repo.NewSessionMediaRepo(pool)

	mine, _, err := mr.Create(ctx, newSessionMedia(tenantID, studentID, uuid.NewString()))
	if err != nil {
		t.Fatalf("criar: %v", err)
	}
	other, _, err := mr.Create(ctx, newSessionMedia(tenantID, newID(), uuid.NewString()))
	if err != nil {
		t.Fatalf("criar de outro aluno: %v", err)
	}
	sameID, _, err := mr.Create(ctx, newSessionMedia(otherTenant, studentID, uuid.NewString()))
	if err != nil {
		t.Fatalf("criar em outro tenant: %v", err)
	}
	if _, err := mr.Ack(ctx, tenantID, other.ID, coachID, time.Now()); err != nil {
		t.Fatalf("ack: %v", err)
	}

	erasure := repo.NewErasureRepo(pool)
	if err := erasure.EraseUser(ctx, tenantID, studentID); err != nil {
		t.Fatalf("excluir aluno: %v", err)
	}
	if _, err := mr.Get(ctx, tenantID, mine.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("a mídia do aluno deveria ter sido excluída, veio %v", err)
	}
	if _, err := mr.Get(ctx, otherTenant, sameID.ID); err != nil {
		t.Fatalf("a mídia do mesmo UUID em outro tenant não pode ser tocada: %v", err)
	}

	if err := erasure.EraseUser(ctx, tenantID, coachID); err != nil {
		t.Fatalf("excluir coach: %v", err)
	}
	got, err := mr.Get(ctx, tenantID, other.ID)
	if err != nil || got.AckedBy != repo.AnonymousUserID {
		t.Fatalf("quem deu ciência deveria ficar anônimo: %+v err=%v", got, err)
	}
}
