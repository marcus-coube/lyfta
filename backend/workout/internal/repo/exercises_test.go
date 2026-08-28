package repo_test

import (
	"context"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// requireSeed garante que a biblioteca global (seed/exercises_seed.sql) está
// carregada — o Aceite do P1.3 é sobre ela. Mesma regra do banco: no CI é
// falha, fora dele é skip com a receita.
func requireSeed(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	items, _, err := repo.NewExerciseRepo(pool).List(context.Background(), newTenant(), domain.ExerciseFilter{
		Query: "supino reto", Locale: domain.LocalePtBR,
	})
	if err != nil {
		t.Fatalf("listar biblioteca: %v", err)
	}
	for _, item := range items {
		if item.IsGlobal() {
			return
		}
	}
	skipOrFail(t, "biblioteca global ausente; rode: psql -U postgres -d lyfta_workout -f seed/exercises_seed.sql")
}

// TestSearchFindsSeededGlobalExercise cobre a primeira metade do Aceite do
// P1.3: busca em pt-BR encontra exercício global seedado — sem acento e sem
// caixa alta, que é como o professor digita.
func TestSearchFindsSeededGlobalExercise(t *testing.T) {
	pool := testPool(t)
	requireSeed(t, pool)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()

	items, _, err := exercises.List(ctx, newTenant(), domain.ExerciseFilter{
		Query: "TRICEPS", Locale: domain.LocalePtBR,
	})
	if err != nil {
		t.Fatalf("buscar: %v", err)
	}

	var found *domain.ExerciseListItem
	for i := range items {
		if items[i].DisplayName == "Tríceps testa" {
			found = &items[i]
		}
	}
	if found == nil {
		t.Fatalf("busca por \"TRICEPS\" não achou o exercício acentuado; veio %v", names(items))
	}
	if !found.IsGlobal() {
		t.Fatalf("exercício do seed deveria ser global, veio tenant %q", found.TenantID)
	}
	if found.NameLocale != domain.LocalePtBR {
		t.Fatalf("esperava texto em pt-BR, veio %q", found.NameLocale)
	}
	if found.Instructions == "" {
		t.Fatal("exercício do seed deveria trazer instruções traduzidas")
	}
}

// TestListFallsBackToNextLocale cobre a cascata do ADR-011 §2: pedindo pt-PT,
// um exercício sem tradução portuguesa volta em pt-BR — e um que tem volta em
// pt-PT.
func TestListFallsBackToNextLocale(t *testing.T) {
	pool := testPool(t)
	requireSeed(t, pool)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()
	tenantID := newTenant()

	marker := uniqueName("Puxador")
	created, err := exercises.Create(ctx, domain.Exercise{
		TenantID: tenantID, Name: marker, PrimaryMuscle: "back", Equipment: "cable",
	}, []domain.ExerciseTranslation{
		{TenantID: tenantID, Locale: domain.LocalePtBR, Name: marker + " BR"},
		{TenantID: tenantID, Locale: domain.LocaleEN, Name: marker + " EN"},
	})
	if err != nil {
		t.Fatalf("criar exercício: %v", err)
	}

	item := findByID(t, exercises, tenantID, domain.LocalePtPT, marker, created.ID)
	if item.NameLocale != domain.LocalePtBR || item.DisplayName != marker+" BR" {
		t.Fatalf("pt-PT deveria cair em pt-BR, veio %q/%q", item.NameLocale, item.DisplayName)
	}

	// O exercício global equivalente tem os três locales: pedindo pt-PT vem o
	// nome português, não o brasileiro.
	items, _, err := exercises.List(ctx, tenantID, domain.ExerciseFilter{
		Query: "agachamento com barra", Locale: domain.LocalePtPT,
	})
	if err != nil {
		t.Fatalf("buscar global: %v", err)
	}
	if len(items) == 0 || items[0].NameLocale != domain.LocalePtPT {
		t.Fatalf("esperava o global em pt-PT, veio %v", names(items))
	}
}

// TestListSeparatesTenantLibraries cobre a segunda metade do Aceite: o
// exercício custom do tenant A não aparece para o tenant B, mas a biblioteca
// global aparece para os dois (ADR-010 §3).
func TestListSeparatesTenantLibraries(t *testing.T) {
	pool := testPool(t)
	requireSeed(t, pool)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()

	marker := uniqueName("Remada do coach")
	if _, err := exercises.Create(ctx, domain.Exercise{
		TenantID: tenantA, Name: marker, PrimaryMuscle: "back", Equipment: "machine",
	}, nil); err != nil {
		t.Fatalf("criar exercício custom: %v", err)
	}

	visibleToA, _, err := exercises.List(ctx, tenantA, domain.ExerciseFilter{Query: marker})
	if err != nil {
		t.Fatalf("listar para A: %v", err)
	}
	if len(visibleToA) != 1 || visibleToA[0].DisplayName != marker {
		t.Fatalf("tenant A deveria ver o próprio exercício, veio %v", names(visibleToA))
	}

	visibleToB, _, err := exercises.List(ctx, tenantB, domain.ExerciseFilter{Query: marker})
	if err != nil {
		t.Fatalf("listar para B: %v", err)
	}
	if len(visibleToB) != 0 {
		t.Fatalf("tenant B não deveria ver exercício custom de A, veio %v", names(visibleToB))
	}

	globals, _, err := exercises.List(ctx, tenantB, domain.ExerciseFilter{Query: "supino reto"})
	if err != nil {
		t.Fatalf("listar globais para B: %v", err)
	}
	if len(globals) == 0 {
		t.Fatal("tenant B deveria enxergar a biblioteca global")
	}
}

// TestListFiltersAndPaginates verifica os filtros da taxonomia e o cursor
// keyset: página a página sem repetir nem pular exercício.
func TestListFiltersAndPaginates(t *testing.T) {
	pool := testPool(t)
	requireSeed(t, pool)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()
	tenantID := newTenant()

	filter := domain.ExerciseFilter{PrimaryMuscle: "chest", Locale: domain.LocalePtBR}
	all, hasMore, err := exercises.List(ctx, tenantID, filter)
	if err != nil {
		t.Fatalf("listar peito: %v", err)
	}
	if len(all) < 3 || hasMore {
		t.Fatalf("esperava a lista completa de peito numa página, veio %d (hasMore=%v)", len(all), hasMore)
	}
	for _, item := range all {
		if item.PrimaryMuscle != "chest" {
			t.Fatalf("filtro de músculo vazou %q", item.PrimaryMuscle)
		}
	}

	paged := []string{}
	pageFilter := filter
	pageFilter.Limit = 2
	for {
		items, more, err := exercises.List(ctx, tenantID, pageFilter)
		if err != nil {
			t.Fatalf("paginar: %v", err)
		}
		for _, item := range items {
			paged = append(paged, item.ID)
		}
		if !more {
			break
		}
		last := items[len(items)-1]
		pageFilter.CursorName, pageFilter.CursorID = last.SortKey, last.ID
	}

	if len(paged) != len(all) {
		t.Fatalf("paginação devolveu %d itens, lista inteira tem %d", len(paged), len(all))
	}
	for i, id := range paged {
		if all[i].ID != id {
			t.Fatalf("ordem divergiu na posição %d: %s vs %s", i, id, all[i].ID)
		}
	}
}

// TestUpdateRejectsGlobalExercise garante que a biblioteca global continua
// somente leitura mesmo pela via do repositório: o RLS não devolve linha.
func TestUpdateRejectsGlobalExercise(t *testing.T) {
	pool := testPool(t)
	requireSeed(t, pool)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()
	tenantID := newTenant()

	items, _, err := exercises.List(ctx, tenantID, domain.ExerciseFilter{Query: "supino reto"})
	if err != nil || len(items) == 0 {
		t.Fatalf("localizar global do seed: %v (%d itens)", err, len(items))
	}

	_, err = exercises.Update(ctx, domain.Exercise{
		ID: items[0].ID, TenantID: tenantID, Name: "Sequestrado",
		PrimaryMuscle: "chest", Equipment: "barbell", Level: domain.LevelBeginner,
	}, nil)
	if err != repo.ErrNotFound {
		t.Fatalf("esperava ErrNotFound ao editar global, veio %v", err)
	}
}

// TestUpdateReplacesTranslations confirma o upsert de tradução e que o
// arquivamento tira o exercício da listagem.
func TestUpdateReplacesTranslations(t *testing.T) {
	pool := testPool(t)
	exercises := repo.NewExerciseRepo(pool)
	ctx := context.Background()
	tenantID := newTenant()

	marker := uniqueName("Crucifixo do coach")
	created, err := exercises.Create(ctx, domain.Exercise{
		TenantID: tenantID, Name: marker, PrimaryMuscle: "chest", Equipment: "dumbbell",
	}, []domain.ExerciseTranslation{
		{TenantID: tenantID, Locale: domain.LocalePtBR, Name: marker, Instructions: "versão 1"},
	})
	if err != nil {
		t.Fatalf("criar: %v", err)
	}

	if _, err := exercises.Update(ctx, domain.Exercise{
		ID: created.ID, TenantID: tenantID, Name: marker,
		PrimaryMuscle: "chest", Equipment: "cable", Level: domain.LevelAdvanced,
	}, []domain.ExerciseTranslation{
		{TenantID: tenantID, Locale: domain.LocalePtBR, Name: marker, Instructions: "versão 2"},
	}); err != nil {
		t.Fatalf("atualizar: %v", err)
	}

	item := findByID(t, exercises, tenantID, domain.LocalePtBR, marker, created.ID)
	if item.Instructions != "versão 2" || item.Equipment != "cable" || item.Level != domain.LevelAdvanced {
		t.Fatalf("update não persistiu: %+v", item)
	}

	if _, err := exercises.Update(ctx, domain.Exercise{
		ID: created.ID, TenantID: tenantID, Name: marker,
		PrimaryMuscle: "chest", Equipment: "cable", Level: domain.LevelAdvanced,
		Status: domain.ExerciseStatusArchived,
	}, nil); err != nil {
		t.Fatalf("arquivar: %v", err)
	}
	remaining, _, err := exercises.List(ctx, tenantID, domain.ExerciseFilter{Query: marker})
	if err != nil {
		t.Fatalf("listar após arquivar: %v", err)
	}
	if len(remaining) != 0 {
		t.Fatalf("exercício arquivado não deveria aparecer na biblioteca, veio %v", names(remaining))
	}
}

func findByID(t *testing.T, exercises *repo.ExerciseRepo, tenantID string, locale domain.Locale, query, id string) domain.ExerciseListItem {
	t.Helper()
	items, _, err := exercises.List(context.Background(), tenantID, domain.ExerciseFilter{
		Query: query, Locale: locale,
	})
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	for _, item := range items {
		if item.ID == id {
			return item
		}
	}
	t.Fatalf("exercício %s não veio na busca %q: %v", id, query, names(items))
	return domain.ExerciseListItem{}
}

// uniqueName evita colisão entre execuções do teste no mesmo banco de dev, que
// não é limpo entre rodadas.
func uniqueName(prefix string) string {
	return prefix + " " + strings.ToUpper(uuid.NewString()[:8])
}

func names(items []domain.ExerciseListItem) []string {
	out := make([]string, 0, len(items))
	for _, item := range items {
		out = append(out, item.DisplayName)
	}
	return out
}
