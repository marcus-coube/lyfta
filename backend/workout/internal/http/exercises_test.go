package http_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// testPool abre o pool contra o Postgres de dev, com a mesma regra do
// internal/repo: pula fora do CI, falha dentro dele (P0.7). Os dois pacotes de
// teste não compartilham helper de propósito — são pacotes distintos e o
// duplicado é uma função de seis linhas.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_workout?sslmode=disable"
	}
	pool, err := repo.NewPool(context.Background(), dsn)
	if err != nil {
		if os.Getenv("CI") != "" {
			t.Fatalf("banco indisponível no CI: %v", err)
		}
		t.Skipf("banco indisponível para teste de integração: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

type apiExercise struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Instructions  string `json:"instructions"`
	Locale        string `json:"locale"`
	PrimaryMuscle string `json:"primary_muscle"`
	Equipment     string `json:"equipment"`
	Level         string `json:"level"`
	MediaURL      string `json:"media_url"`
	IsGlobal      bool   `json:"is_global"`
	Status        string `json:"status"`
	CanonicalName string `json:"canonical_name"`
	Translations  []struct {
		Locale       string `json:"locale"`
		Name         string `json:"name"`
		Instructions string `json:"instructions"`
	} `json:"translations"`
}

type apiExerciseList struct {
	Items      []apiExercise `json:"items"`
	NextCursor string        `json:"next_cursor"`
}

type apiError struct {
	Code   string         `json:"code"`
	Params map[string]any `json:"params"`
}

func do(t *testing.T, handler http.Handler, method, target, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("serializar corpo: %v", err)
		}
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, target, reader)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func decodeList(t *testing.T, rec *httptest.ResponseRecorder) apiExerciseList {
	t.Helper()
	var list apiExerciseList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decodificar lista: %v (%s)", err, rec.Body.String())
	}
	return list
}

func decodeError(t *testing.T, rec *httptest.ResponseRecorder) apiError {
	t.Helper()
	var e apiError
	if err := json.Unmarshal(rec.Body.Bytes(), &e); err != nil {
		t.Fatalf("decodificar erro: %v (%s)", err, rec.Body.String())
	}
	return e
}

// libraryFixture monta o router com banco de verdade e devolve tokens de dois
// tenants — é o cenário do Aceite do P1.3.
func libraryFixture(t *testing.T) (handler http.Handler, coachA, coachB, studentA string, tenantA string) {
	t.Helper()
	pool := testPool(t)
	publicPEM, priv := newTestKeys(t)
	handler = newTestRouterWithPool(t, publicPEM, pool)

	tenantA, tenantB := uuid.NewString(), uuid.NewString()
	expires := time.Now().Add(time.Minute)
	return handler,
		signToken(t, priv, tenantA, []string{"coach"}, expires),
		signToken(t, priv, tenantB, []string{"coach"}, expires),
		signToken(t, priv, tenantA, []string{"student"}, expires),
		tenantA
}

// requireSeededLibrary garante o seed global carregado — o Aceite fala dele.
func requireSeededLibrary(t *testing.T, handler http.Handler, token string) apiExercise {
	t.Helper()
	rec := do(t, handler, http.MethodGet, "/v1/exercises?q=supino+reto", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("listar biblioteca: %d %s", rec.Code, rec.Body.String())
	}
	for _, item := range decodeList(t, rec).Items {
		if item.IsGlobal {
			return item
		}
	}
	if os.Getenv("CI") != "" {
		t.Fatal("biblioteca global ausente no CI: seed/exercises_seed.sql não foi aplicado")
	}
	t.Skip("biblioteca global ausente; rode: psql -U postgres -d lyfta_workout -f seed/exercises_seed.sql")
	return apiExercise{}
}

// TestExerciseLibraryEndToEnd é o Aceite do P1.3 pela API: busca em pt-BR acha
// o exercício global do seed, o coach cria um custom e só o tenant dele vê.
func TestExerciseLibraryEndToEnd(t *testing.T) {
	handler, coachA, coachB, _, _ := libraryFixture(t)
	global := requireSeededLibrary(t, handler, coachA)

	if global.Name != "Supino reto com barra" || global.Instructions == "" {
		t.Fatalf("global do seed veio errado em pt-BR: %+v", global)
	}

	custom := map[string]any{
		"name":           "Remada Lyfta " + strings.ToUpper(uuid.NewString()[:8]),
		"primary_muscle": "back",
		"equipment":      "machine",
		"level":          "intermediate",
		"instructions":   "Puxe até o abdômen mantendo o tronco firme.",
	}
	rec := do(t, handler, http.MethodPost, "/v1/exercises", coachA, custom)
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar exercício custom: %d %s", rec.Code, rec.Body.String())
	}
	var created apiExercise
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decodificar criado: %v", err)
	}
	if created.IsGlobal || created.Status != "active" {
		t.Fatalf("custom deveria nascer do tenant e ativo: %+v", created)
	}

	// O coach do próprio tenant encontra na busca...
	rec = do(t, handler, http.MethodGet, "/v1/exercises?q="+urlQuery(custom["name"].(string)), coachA, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("buscar custom: %d %s", rec.Code, rec.Body.String())
	}
	items := decodeList(t, rec).Items
	if len(items) != 1 || items[0].ID != created.ID {
		t.Fatalf("coach do tenant deveria achar o próprio exercício, veio %+v", items)
	}

	// ...e o coach do outro tenant não, mas continua vendo a biblioteca global.
	rec = do(t, handler, http.MethodGet, "/v1/exercises?q="+urlQuery(custom["name"].(string)), coachB, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("buscar custom no tenant B: %d %s", rec.Code, rec.Body.String())
	}
	if items := decodeList(t, rec).Items; len(items) != 0 {
		t.Fatalf("tenant B não deveria ver exercício custom de A, veio %+v", items)
	}
	requireSeededLibrary(t, handler, coachB)

	// Detalhe traz as traduções para a tela de edição; `instructions` do corpo
	// virou tradução no locale da claim (pt-BR).
	rec = do(t, handler, http.MethodGet, "/v1/exercises/"+created.ID, coachA, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("detalhe: %d %s", rec.Code, rec.Body.String())
	}
	var detail apiExercise
	if err := json.Unmarshal(rec.Body.Bytes(), &detail); err != nil {
		t.Fatalf("decodificar detalhe: %v", err)
	}
	if len(detail.Translations) != 1 || detail.Translations[0].Locale != "pt-BR" {
		t.Fatalf("esperava uma tradução pt-BR, veio %+v", detail.Translations)
	}
	if detail.CanonicalName != custom["name"] {
		t.Fatalf("canonical_name divergiu: %q", detail.CanonicalName)
	}

	// Editar o próprio exercício é permitido.
	updated := map[string]any{
		"name": custom["name"], "primary_muscle": "lats", "equipment": "cable", "level": "advanced",
	}
	rec = do(t, handler, http.MethodPut, "/v1/exercises/"+created.ID, coachA, updated)
	if rec.Code != http.StatusOK {
		t.Fatalf("editar custom: %d %s", rec.Code, rec.Body.String())
	}

	// O tenant B não enxerga o exercício de A nem pelo id direto.
	rec = do(t, handler, http.MethodGet, "/v1/exercises/"+created.ID, coachB, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("esperava 404 para o tenant B, veio %d", rec.Code)
	}
}

// TestUpdateGlobalExerciseIsForbidden: a biblioteca global é somente leitura
// (ADR-010 §3) e a API diz isso com um código próprio — não com 404, que
// mandaria a UI esconder um exercício que está na tela.
func TestUpdateGlobalExerciseIsForbidden(t *testing.T) {
	handler, coachA, _, _, _ := libraryFixture(t)
	global := requireSeededLibrary(t, handler, coachA)

	rec := do(t, handler, http.MethodPut, "/v1/exercises/"+global.ID, coachA, map[string]any{
		"name": "Supino sequestrado", "primary_muscle": "chest", "equipment": "barbell",
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("esperava 403 ao editar global, veio %d %s", rec.Code, rec.Body.String())
	}
	if code := decodeError(t, rec).Code; code != "exercise_is_global" {
		t.Fatalf("esperava code exercise_is_global, veio %q", code)
	}
}

// TestWriteRequiresCoach: o aluno lê a biblioteca (o treino dele mostra nome e
// mídia) mas não escreve nela.
func TestWriteRequiresCoach(t *testing.T) {
	handler, coachA, _, studentA, _ := libraryFixture(t)
	requireSeededLibrary(t, handler, studentA)

	rec := do(t, handler, http.MethodPost, "/v1/exercises", studentA, map[string]any{
		"name": "Exercício do aluno", "primary_muscle": "chest", "equipment": "barbell",
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("aluno não deveria criar exercício, veio %d", rec.Code)
	}

	rec = do(t, handler, http.MethodGet, "/v1/exercises", "", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("sem token deveria ser 401, veio %d", rec.Code)
	}
	_ = coachA
}

// TestCreateExerciseValidation cobre as recusas de contrato: taxonomia inválida
// (ADR-010 §4), mídia fora da pasta do tenant (par do presign do P1.2) e
// cursor corrompido.
func TestCreateExerciseValidation(t *testing.T) {
	handler, coachA, _, _, tenantA := libraryFixture(t)

	cases := []struct {
		name  string
		body  map[string]any
		field string
	}{
		{"sem nome", map[string]any{"primary_muscle": "chest", "equipment": "barbell"}, "name"},
		{"músculo fora da taxonomia", map[string]any{"name": "X", "primary_muscle": "peitoral", "equipment": "barbell"}, "primary_muscle"},
		{"equipamento fora da taxonomia", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barra"}, "equipment"},
		{"nível inválido", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barbell", "level": "deus"}, "level"},
		{"mídia sem tipo", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barbell",
			"media_url": "http://localhost:9000/lyfta-media/tenants/" + tenantA + "/exercises/a.gif"}, "media_url"},
		{"mídia de outro tenant", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barbell",
			"media_url":  "http://localhost:9000/lyfta-media/tenants/" + uuid.NewString() + "/exercises/a.gif",
			"media_type": "gif"}, "media_url"},
		{"tradução em locale desconhecido", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barbell",
			"translations": []map[string]string{{"locale": "fr", "name": "X"}}}, "translations.locale"},
		{"status no cadastro", map[string]any{"name": "X", "primary_muscle": "chest", "equipment": "barbell",
			"status": "archived"}, "status"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := do(t, handler, http.MethodPost, "/v1/exercises", coachA, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("esperava 400, veio %d %s", rec.Code, rec.Body.String())
			}
			apiErr := decodeError(t, rec)
			if apiErr.Code != "validation_error" || apiErr.Params["field"] != tc.field {
				t.Fatalf("esperava validation_error em %q, veio %+v", tc.field, apiErr)
			}
		})
	}

	rec := do(t, handler, http.MethodGet, "/v1/exercises?cursor=nao-e-base64!", coachA, nil)
	if rec.Code != http.StatusBadRequest || decodeError(t, rec).Code != "invalid_cursor" {
		t.Fatalf("cursor corrompido deveria dar invalid_cursor, veio %d %s", rec.Code, rec.Body.String())
	}
	rec = do(t, handler, http.MethodGet, "/v1/exercises?locale=fr", coachA, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("locale desconhecido deveria dar 400, veio %d", rec.Code)
	}
}

// TestListPaginatesWithCursor: o cliente devolve o next_cursor recebido e
// nenhuma página repete item.
func TestListPaginatesWithCursor(t *testing.T) {
	handler, coachA, _, _, _ := libraryFixture(t)
	requireSeededLibrary(t, handler, coachA)

	seen := map[string]bool{}
	target := "/v1/exercises?muscle=chest&limit=2"
	for pages := 0; pages < 10; pages++ {
		rec := do(t, handler, http.MethodGet, target, coachA, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("listar página: %d %s", rec.Code, rec.Body.String())
		}
		list := decodeList(t, rec)
		if len(list.Items) == 0 {
			t.Fatal("página vazia com cursor ainda aberto")
		}
		for _, item := range list.Items {
			if seen[item.ID] {
				t.Fatalf("item repetido entre páginas: %s", item.Name)
			}
			seen[item.ID] = true
		}
		if list.NextCursor == "" {
			if len(seen) < 3 {
				t.Fatalf("esperava mais exercícios de peito na biblioteca, vieram %d", len(seen))
			}
			return
		}
		target = "/v1/exercises?muscle=chest&limit=2&cursor=" + urlQuery(list.NextCursor)
	}
	t.Fatal("paginação não terminou em 10 páginas")
}

func urlQuery(v string) string { return strings.ReplaceAll(url.QueryEscape(v), "+", "%20") }

// TestLibraryFollowsAcceptLanguage é o Aceite do P8.3: o idioma da tela (cabeçalho)
// vence o locale do tenant (claim) e o `?locale=` vence o cabeçalho.
func TestLibraryFollowsAcceptLanguage(t *testing.T) {
	handler, coachA, _, _, _ := libraryFixture(t)
	global := requireSeededLibrary(t, handler, coachA)

	get := func(target, lang string) apiExercise {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, target, nil)
		req.Header.Set("Authorization", "Bearer "+coachA)
		if lang != "" {
			req.Header.Set("Accept-Language", lang)
		}
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s: %d %s", target, rec.Code, rec.Body.String())
		}
		for _, item := range decodeList(t, rec).Items {
			if item.ID == global.ID {
				return item
			}
		}
		t.Fatalf("exercício do seed ausente em %s", target)
		return apiExercise{}
	}

	en := get("/v1/exercises?q=supino+reto", "en")
	if en.Locale != "en" || en.Name == global.Name {
		t.Fatalf("Accept-Language: en deveria traduzir o nome, veio %+v", en)
	}
	if got := get("/v1/exercises?q=supino+reto", ""); got.Name != global.Name {
		t.Fatalf("sem cabeçalho cai no locale da claim: %+v", got)
	}
	if got := get("/v1/exercises?q=supino+reto&locale=pt-BR", "en"); got.Name != global.Name {
		t.Fatalf("?locale= deveria vencer o cabeçalho: %+v", got)
	}
}
