package repo_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

func f(v float64) *float64 { return &v }

// TestMeasurementRepoRoundTrip cobre o fluxo feliz da P2.3: criar, listar em
// ordem decrescente e apagar — e que apagar o registro de outro aluno (mesmo
// tenant) não é permitido.
func TestMeasurementRepoRoundTrip(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	repoM := repo.NewMeasurementRepo(pool)
	tenantID, studentA, studentB := newID(), newID(), newID()

	older := domain.BodyMeasurement{
		TenantID: tenantID, StudentID: studentA,
		MeasuredAt: time.Now().AddDate(0, 0, -10), WeightKg: f(82), WaistCm: f(92),
	}
	newer := domain.BodyMeasurement{
		TenantID: tenantID, StudentID: studentA,
		MeasuredAt: time.Now(), WeightKg: f(80), WaistCm: f(90),
	}
	if _, err := repoM.Create(ctx, older); err != nil {
		t.Fatalf("criar medida antiga: %v", err)
	}
	createdNewer, err := repoM.Create(ctx, newer)
	if err != nil {
		t.Fatalf("criar medida recente: %v", err)
	}

	// Uma medida do aluno B, mesmo tenant: não pode vazar para a lista de A.
	if _, err := repoM.Create(ctx, domain.BodyMeasurement{
		TenantID: tenantID, StudentID: studentB, MeasuredAt: time.Now(), WeightKg: f(60),
	}); err != nil {
		t.Fatalf("criar medida do aluno B: %v", err)
	}

	items, hasMore, err := repoM.List(ctx, tenantID, studentA, nil, "", 10)
	if err != nil {
		t.Fatalf("listar medidas: %v", err)
	}
	if hasMore {
		t.Fatal("duas medidas cabem numa página, não deveria haver mais")
	}
	if len(items) != 2 {
		t.Fatalf("esperava 2 medidas do aluno A, veio %d", len(items))
	}
	if items[0].ID != createdNewer.ID {
		t.Fatalf("esperava a mais recente primeiro, veio %+v", items[0])
	}
	if items[0].WeightKg == nil || *items[0].WeightKg != 80 {
		t.Fatalf("weight_kg da mais recente veio errado: %+v", items[0].WeightKg)
	}

	// Apagar a medida de A pelo student_id de B não encontra nada.
	if err := repoM.Delete(ctx, tenantID, studentB, createdNewer.ID); !errors.Is(err, repo.ErrNotFound) {
		t.Fatalf("esperava ErrNotFound apagando medida de outro aluno, veio %v", err)
	}
	if err := repoM.Delete(ctx, tenantID, studentA, createdNewer.ID); err != nil {
		t.Fatalf("apagar a própria medida: %v", err)
	}
	items, _, err = repoM.List(ctx, tenantID, studentA, nil, "", 10)
	if err != nil {
		t.Fatalf("listar após apagar: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("esperava 1 medida restante, veio %d", len(items))
	}
}

// TestMeasurementRepoPagination cobre o cursor keyset: página cheia sinaliza
// mais itens, e a segunda página não repete o que já veio.
func TestMeasurementRepoPagination(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	repoM := repo.NewMeasurementRepo(pool)
	tenantID, studentID := newID(), newID()

	for i := 0; i < 3; i++ {
		if _, err := repoM.Create(ctx, domain.BodyMeasurement{
			TenantID: tenantID, StudentID: studentID,
			MeasuredAt: time.Now().AddDate(0, 0, -i), WeightKg: f(float64(80 + i)),
		}); err != nil {
			t.Fatalf("criar medida %d: %v", i, err)
		}
	}

	page1, hasMore, err := repoM.List(ctx, tenantID, studentID, nil, "", 2)
	if err != nil {
		t.Fatalf("listar página 1: %v", err)
	}
	if !hasMore || len(page1) != 2 {
		t.Fatalf("esperava página cheia com mais itens, veio %d itens, hasMore=%v", len(page1), hasMore)
	}

	last := page1[len(page1)-1]
	page2, hasMore, err := repoM.List(ctx, tenantID, studentID, &last.MeasuredAt, last.ID, 2)
	if err != nil {
		t.Fatalf("listar página 2: %v", err)
	}
	if hasMore || len(page2) != 1 {
		t.Fatalf("esperava a última página com 1 item, veio %d itens, hasMore=%v", len(page2), hasMore)
	}
	for _, p1 := range page1 {
		for _, p2 := range page2 {
			if p1.ID == p2.ID {
				t.Fatalf("página 2 repetiu um item da página 1: %s", p1.ID)
			}
		}
	}
}

// TestBioimpedanceRepoRoundTrip espelha o teste de medidas para o segundo
// agregado.
func TestBioimpedanceRepoRoundTrip(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	repoB := repo.NewBioimpedanceRepo(pool)
	tenantID, studentID := newID(), newID()

	if _, err := repoB.Create(ctx, domain.BioimpedanceRecord{
		TenantID: tenantID, StudentID: studentID,
		MeasuredAt: time.Now().AddDate(0, 0, -5), BodyFatPct: f(20),
	}); err != nil {
		t.Fatalf("criar leitura antiga: %v", err)
	}
	recent, err := repoB.Create(ctx, domain.BioimpedanceRecord{
		TenantID: tenantID, StudentID: studentID,
		MeasuredAt: time.Now(), BodyFatPct: f(18.4),
	})
	if err != nil {
		t.Fatalf("criar leitura recente: %v", err)
	}

	items, _, err := repoB.List(ctx, tenantID, studentID, nil, "", 10)
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	if len(items) != 2 || items[0].ID != recent.ID {
		t.Fatalf("esperava a mais recente primeiro: %+v", items)
	}

	if err := repoB.Delete(ctx, tenantID, studentID, recent.ID); err != nil {
		t.Fatalf("apagar: %v", err)
	}
	items, _, err = repoB.List(ctx, tenantID, studentID, nil, "", 10)
	if err != nil {
		t.Fatalf("listar após apagar: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("esperava 1 registro restante, veio %d", len(items))
	}
}

// TestPhotoRepoRoundTrip cobre criação, listagem, contagem e exclusão de
// fotos de evolução.
func TestPhotoRepoRoundTrip(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	repoP := repo.NewPhotoRepo(pool)
	tenantID, studentID := newID(), newID()

	key := "tenants/" + tenantID + "/students/" + studentID + "/photos/" + uuid.NewString() + ".jpg"
	photo, err := repoP.Create(ctx, domain.ProgressPhoto{
		TenantID: tenantID, StudentID: studentID, TakenAt: time.Now(),
		Pose: domain.PoseFront, MediaKey: key,
	})
	if err != nil {
		t.Fatalf("criar foto: %v", err)
	}

	n, err := repoP.Count(ctx, tenantID, studentID)
	if err != nil {
		t.Fatalf("contar fotos: %v", err)
	}
	if n != 1 {
		t.Fatalf("esperava 1 foto, veio %d", n)
	}

	items, _, err := repoP.List(ctx, tenantID, studentID, nil, "", 10)
	if err != nil {
		t.Fatalf("listar fotos: %v", err)
	}
	if len(items) != 1 || items[0].MediaKey != key {
		t.Fatalf("foto veio errada: %+v", items)
	}

	if err := repoP.Delete(ctx, tenantID, studentID, photo.ID); err != nil {
		t.Fatalf("apagar foto: %v", err)
	}
	n, err = repoP.Count(ctx, tenantID, studentID)
	if err != nil {
		t.Fatalf("contar após apagar: %v", err)
	}
	if n != 0 {
		t.Fatalf("esperava 0 fotos após apagar, veio %d", n)
	}
}
