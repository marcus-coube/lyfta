package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// TestConversationGetOrCreateIsIdempotent cobre a base do P3.2: abrir o chat
// com um aluno que já tem conversa não duplica a linha — devolve a mesma
// (unique de tenant+student+coach da migration 0001).
func TestConversationGetOrCreateIsIdempotent(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID := newID(), newID(), newID()
	repoConv := repo.NewConversationRepo(pool)

	first, err := repoConv.GetOrCreate(ctx, tenantID, studentID, coachID)
	if err != nil {
		t.Fatalf("primeira chamada: %v", err)
	}
	second, err := repoConv.GetOrCreate(ctx, tenantID, studentID, coachID)
	if err != nil {
		t.Fatalf("segunda chamada: %v", err)
	}
	if first.ID != second.ID {
		t.Fatalf("get-or-create deveria devolver a mesma conversa: %s != %s", first.ID, second.ID)
	}
}

// TestConversationListForUserSeesBothRoles confere que a mesma conversa
// aparece tanto para o aluno quanto para o coach, e que um terceiro usuário
// (sem participar) não vê nada.
func TestConversationListForUserSeesBothRoles(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID, outsiderID := newID(), newID(), newID(), newID()
	repoConv := repo.NewConversationRepo(pool)

	if _, err := repoConv.GetOrCreate(ctx, tenantID, studentID, coachID); err != nil {
		t.Fatalf("criar conversa: %v", err)
	}

	forStudent, err := repoConv.ListForUser(ctx, tenantID, studentID)
	if err != nil || len(forStudent) != 1 {
		t.Fatalf("aluno deveria ver 1 conversa: items=%d err=%v", len(forStudent), err)
	}
	forCoach, err := repoConv.ListForUser(ctx, tenantID, coachID)
	if err != nil || len(forCoach) != 1 {
		t.Fatalf("coach deveria ver 1 conversa: items=%d err=%v", len(forCoach), err)
	}
	forOutsider, err := repoConv.ListForUser(ctx, tenantID, outsiderID)
	if err != nil || len(forOutsider) != 0 {
		t.Fatalf("usuário de fora não deveria ver conversa nenhuma: items=%d err=%v", len(forOutsider), err)
	}
}

// TestMessageListCursorPagination confere o keyset por (created_at, id): a
// segunda página não repete nem pula mensagens.
func TestMessageListCursorPagination(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID := newID(), newID(), newID()
	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)

	conv, err := conversations.GetOrCreate(ctx, tenantID, studentID, coachID)
	if err != nil {
		t.Fatalf("criar conversa: %v", err)
	}

	var created []domain.Message
	for i := 0; i < 3; i++ {
		m, err := messages.Create(ctx, domain.Message{
			TenantID: tenantID, ConversationID: conv.ID, SenderID: studentID,
			Type: domain.MessageTypeText, Body: "msg",
		})
		if err != nil {
			t.Fatalf("criar mensagem %d: %v", i, err)
		}
		created = append(created, m)
		time.Sleep(2 * time.Millisecond) // garante created_at estritamente crescente
	}

	page1, hasMore, err := messages.List(ctx, tenantID, conv.ID, nil, "", 2)
	if err != nil {
		t.Fatalf("listar página 1: %v", err)
	}
	if len(page1) != 2 || !hasMore {
		t.Fatalf("página 1 deveria ter 2 itens e hasMore=true, veio %d/%v", len(page1), hasMore)
	}
	if page1[0].ID != created[2].ID || page1[1].ID != created[1].ID {
		t.Fatalf("página 1 fora de ordem (mais recente primeiro)")
	}

	last := page1[len(page1)-1]
	page2, hasMore2, err := messages.List(ctx, tenantID, conv.ID, &last.CreatedAt, last.ID, 2)
	if err != nil {
		t.Fatalf("listar página 2: %v", err)
	}
	if len(page2) != 1 || hasMore2 {
		t.Fatalf("página 2 deveria ter o último item restante, veio %d/%v", len(page2), hasMore2)
	}
	if page2[0].ID != created[0].ID {
		t.Fatalf("página 2 deveria trazer a mensagem mais antiga")
	}
}

// TestMessageMarkReadOnlyAffectsOtherSender confere que marcar como lida só
// afeta mensagens que o leitor não enviou — a mensagem que ele mesmo mandou
// não conta como "não lida" para ele.
func TestMessageMarkReadOnlyAffectsOtherSender(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID := newID(), newID(), newID()
	conversations := repo.NewConversationRepo(pool)
	messages := repo.NewMessageRepo(pool)

	conv, err := conversations.GetOrCreate(ctx, tenantID, studentID, coachID)
	if err != nil {
		t.Fatalf("criar conversa: %v", err)
	}
	if _, err := messages.Create(ctx, domain.Message{
		TenantID: tenantID, ConversationID: conv.ID, SenderID: studentID, Type: domain.MessageTypeText, Body: "do aluno",
	}); err != nil {
		t.Fatalf("mensagem do aluno: %v", err)
	}
	if _, err := messages.Create(ctx, domain.Message{
		TenantID: tenantID, ConversationID: conv.ID, SenderID: coachID, Type: domain.MessageTypeText, Body: "do coach",
	}); err != nil {
		t.Fatalf("mensagem do coach: %v", err)
	}

	// O coach lê: só a mensagem do aluno deveria ser marcada.
	ids, err := messages.MarkRead(ctx, tenantID, conv.ID, coachID)
	if err != nil {
		t.Fatalf("marcar como lida: %v", err)
	}
	if len(ids) != 1 {
		t.Fatalf("esperava 1 mensagem marcada, veio %d", len(ids))
	}

	// Rodar de novo não marca nada a mais — idempotente.
	again, err := messages.MarkRead(ctx, tenantID, conv.ID, coachID)
	if err != nil {
		t.Fatalf("marcar como lida de novo: %v", err)
	}
	if len(again) != 0 {
		t.Fatalf("segunda chamada não deveria marcar nada, marcou %d", len(again))
	}
}
