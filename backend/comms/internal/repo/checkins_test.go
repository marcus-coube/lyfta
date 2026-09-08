package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// TestCheckinCreateIsIdempotent cobre o Aceite do P3.3: reenvio do check-in
// da mesma sessão não cria um segundo registro — a segunda chamada devolve o
// dado da primeira, mesmo com valores diferentes no corpo (o ON CONFLICT não
// atualiza nenhum campo de negócio).
func TestCheckinCreateIsIdempotent(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newID(), newID()
	sessionClientID := uuid.NewString()
	checkins := repo.NewCheckinRepo(pool)

	first, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: sessionClientID,
		Rating: 5, Difficulty: 2, Pain: domain.PainNone,
	})
	if err != nil {
		t.Fatalf("primeiro check-in: %v", err)
	}

	second, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: sessionClientID,
		Rating: 1, Difficulty: 5, Pain: domain.PainStrong, Comment: "reenvio",
	})
	if err != nil {
		t.Fatalf("segundo check-in (reenvio): %v", err)
	}

	if first.ID != second.ID {
		t.Fatalf("reenvio deveria devolver o mesmo check-in: %s != %s", first.ID, second.ID)
	}
	if second.Rating != 5 || second.Pain != domain.PainNone {
		t.Fatalf("reenvio não deveria sobrescrever os dados originais, veio rating=%d pain=%s", second.Rating, second.Pain)
	}

	count, err := countRows(ctx, pool, tenantID, "workout_checkins")
	if err != nil {
		t.Fatalf("contar check-ins: %v", err)
	}
	if count != 1 {
		t.Fatalf("reenvio não deveria criar um segundo registro, existem %d", count)
	}
}

// TestCheckinListOrdersPendingFirst cobre o Aceite: "listagem do coach
// ordena não revisados primeiro" — dado um revisado e dois pendentes, a
// primeira página traz os dois pendentes antes do revisado.
func TestCheckinListOrdersPendingFirst(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachID := newID(), newID(), newID()
	checkins := repo.NewCheckinRepo(pool)

	older, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: uuid.NewString(),
		Rating: 4, Difficulty: 3, Pain: domain.PainNone,
	})
	if err != nil {
		t.Fatalf("criar check-in mais antigo: %v", err)
	}
	if _, err := checkins.Review(ctx, tenantID, older.ID, coachID); err != nil {
		t.Fatalf("revisar check-in mais antigo: %v", err)
	}

	time.Sleep(2 * time.Millisecond)
	pending1, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: uuid.NewString(),
		Rating: 3, Difficulty: 3, Pain: domain.PainMild,
	})
	if err != nil {
		t.Fatalf("criar check-in pendente 1: %v", err)
	}
	time.Sleep(2 * time.Millisecond)
	pending2, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: uuid.NewString(),
		Rating: 2, Difficulty: 4, Pain: domain.PainStrong,
	})
	if err != nil {
		t.Fatalf("criar check-in pendente 2: %v", err)
	}

	items, hasMore, err := checkins.List(ctx, tenantID, "", nil, 50)
	if err != nil {
		t.Fatalf("listar check-ins: %v", err)
	}
	if hasMore {
		t.Fatalf("não deveria haver mais páginas com só 3 registros e limite 50")
	}
	if len(items) != 3 {
		t.Fatalf("esperava 3 check-ins, veio %d", len(items))
	}
	// Não revisados primeiro (mais recente primeiro entre eles), revisado por
	// último.
	if items[0].ID != pending2.ID || items[1].ID != pending1.ID || items[2].ID != older.ID {
		t.Fatalf("ordem incorreta: esperava [%s,%s,%s], veio [%s,%s,%s]",
			pending2.ID, pending1.ID, older.ID, items[0].ID, items[1].ID, items[2].ID)
	}
	if items[2].ReviewedAt == nil {
		t.Fatal("o último item deveria estar revisado")
	}
}

// TestCheckinListPagination confere que o cursor keyset (sort_key +
// created_at + id) não repete nem pula itens ao paginar.
func TestCheckinListPagination(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newID(), newID()
	checkins := repo.NewCheckinRepo(pool)

	var created []domain.WorkoutCheckin
	for i := 0; i < 3; i++ {
		c, err := checkins.Create(ctx, domain.WorkoutCheckin{
			TenantID: tenantID, StudentID: studentID, SessionClientID: uuid.NewString(),
			Rating: 3, Difficulty: 3, Pain: domain.PainNone,
		})
		if err != nil {
			t.Fatalf("criar check-in %d: %v", i, err)
		}
		created = append(created, c)
		time.Sleep(2 * time.Millisecond)
	}

	page1, hasMore, err := checkins.List(ctx, tenantID, "", nil, 2)
	if err != nil {
		t.Fatalf("listar página 1: %v", err)
	}
	if len(page1) != 2 || !hasMore {
		t.Fatalf("página 1 deveria ter 2 itens e hasMore=true, veio %d/%v", len(page1), hasMore)
	}
	if page1[0].ID != created[2].ID || page1[1].ID != created[1].ID {
		t.Fatalf("página 1 fora de ordem (mais recente primeiro)")
	}

	cursor := repo.NewCheckinCursor(page1[len(page1)-1])
	page2, hasMore2, err := checkins.List(ctx, tenantID, "", &cursor, 2)
	if err != nil {
		t.Fatalf("listar página 2: %v", err)
	}
	if len(page2) != 1 || hasMore2 {
		t.Fatalf("página 2 deveria ter o último item restante, veio %d/%v", len(page2), hasMore2)
	}
	if page2[0].ID != created[0].ID {
		t.Fatalf("página 2 deveria trazer o check-in mais antigo")
	}
}

// TestCheckinListFiltersByStudent confere o filtro `?student_id=` — um
// terceiro aluno não aparece na lista do outro.
func TestCheckinListFiltersByStudent(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentA, studentB := newID(), newID(), newID()
	checkins := repo.NewCheckinRepo(pool)

	if _, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentA, SessionClientID: uuid.NewString(),
		Rating: 4, Difficulty: 3, Pain: domain.PainNone,
	}); err != nil {
		t.Fatalf("criar check-in do aluno A: %v", err)
	}
	if _, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentB, SessionClientID: uuid.NewString(),
		Rating: 4, Difficulty: 3, Pain: domain.PainNone,
	}); err != nil {
		t.Fatalf("criar check-in do aluno B: %v", err)
	}

	itemsA, _, err := checkins.List(ctx, tenantID, studentA, nil, 50)
	if err != nil {
		t.Fatalf("listar do aluno A: %v", err)
	}
	if len(itemsA) != 1 || itemsA[0].StudentID != studentA {
		t.Fatalf("esperava só o check-in do aluno A, veio %+v", itemsA)
	}

	itemsAll, _, err := checkins.List(ctx, tenantID, "", nil, 50)
	if err != nil {
		t.Fatalf("listar do tenant inteiro: %v", err)
	}
	if len(itemsAll) != 2 {
		t.Fatalf("esperava os 2 check-ins do tenant, veio %d", len(itemsAll))
	}
}

// TestCheckinReviewIsIdempotent confere que revisar duas vezes não troca
// quem revisou primeiro.
func TestCheckinReviewIsIdempotent(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID, coachA, coachB := newID(), newID(), newID(), newID()
	checkins := repo.NewCheckinRepo(pool)

	c, err := checkins.Create(ctx, domain.WorkoutCheckin{
		TenantID: tenantID, StudentID: studentID, SessionClientID: uuid.NewString(),
		Rating: 3, Difficulty: 3, Pain: domain.PainNone,
	})
	if err != nil {
		t.Fatalf("criar check-in: %v", err)
	}

	first, err := checkins.Review(ctx, tenantID, c.ID, coachA)
	if err != nil {
		t.Fatalf("primeira revisão: %v", err)
	}
	if first.ReviewedBy != coachA || first.ReviewedAt == nil {
		t.Fatalf("esperava reviewed_by=%s, veio %+v", coachA, first)
	}

	second, err := checkins.Review(ctx, tenantID, c.ID, coachB)
	if err != nil {
		t.Fatalf("segunda revisão: %v", err)
	}
	if second.ReviewedBy != coachA {
		t.Fatalf("segunda revisão não deveria trocar o revisor, veio %s", second.ReviewedBy)
	}
	if !second.ReviewedAt.Equal(*first.ReviewedAt) {
		t.Fatalf("segunda revisão não deveria trocar o instante, %v != %v", second.ReviewedAt, first.ReviewedAt)
	}
}

// TestCheckinGetNotFound confere que id inexistente (ou de outro tenant)
// devolve ErrNotFound.
func TestCheckinGetNotFound(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	checkins := repo.NewCheckinRepo(pool)

	_, err := checkins.Get(ctx, newID(), uuid.NewString())
	if err != repo.ErrNotFound {
		t.Fatalf("esperava ErrNotFound, veio %v", err)
	}
}
