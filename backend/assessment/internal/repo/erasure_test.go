package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/marcus-coube/lyfta/assessment/internal/domain"
	"github.com/marcus-coube/lyfta/assessment/internal/repo"
)

// TestEraseUserIsPhysicalAndScoped cobre a exclusão física da exclusão de
// conta (ADR-008 §2, P4.5): medidas, bioimpedância e fotos do aluno somem; o
// outro aluno do tenant e o mesmo UUID num outro tenant (RLS, ADR-001 §6)
// continuam intactos; repetir é seguro.
func TestEraseUserIsPhysicalAndScoped(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, otherTenant := newID(), newID()
	student, neighbour := newID(), newID()
	measurements, bio, photos := repo.NewMeasurementRepo(pool), repo.NewBioimpedanceRepo(pool), repo.NewPhotoRepo(pool)

	seed := func(tenant, who string) {
		t.Helper()
		if _, err := measurements.Create(ctx, domain.BodyMeasurement{TenantID: tenant, StudentID: who, MeasuredAt: time.Now(), WeightKg: f(80)}); err != nil {
			t.Fatalf("medida: %v", err)
		}
		if _, err := bio.Create(ctx, domain.BioimpedanceRecord{TenantID: tenant, StudentID: who, MeasuredAt: time.Now(), BodyFatPct: f(20)}); err != nil {
			t.Fatalf("bioimpedância: %v", err)
		}
		if _, err := photos.Create(ctx, domain.ProgressPhoto{
			TenantID: tenant, StudentID: who, TakenAt: time.Now(), Pose: domain.PoseFront,
			MediaKey: "tenants/" + tenant + "/students/" + who + "/photos/" + newID() + ".jpg",
		}); err != nil {
			t.Fatalf("foto: %v", err)
		}
	}
	seed(tenantID, student)
	seed(tenantID, neighbour)
	seed(otherTenant, student) // mesmo UUID, outro tenant

	erasure := repo.NewErasureRepo(pool)
	for i := 0; i < 2; i++ {
		if err := erasure.EraseUser(ctx, tenantID, student); err != nil {
			t.Fatalf("excluir (%d): %v", i+1, err)
		}
	}

	counts := func(tenant, who string) (m, b, p int) {
		t.Helper()
		ms, _, _ := measurements.List(ctx, tenant, who, nil, "", 50)
		bs, _, _ := bio.List(ctx, tenant, who, nil, "", 50)
		ps, _, _ := photos.List(ctx, tenant, who, nil, "", 50)
		return len(ms), len(bs), len(ps)
	}
	if m, b, p := counts(tenantID, student); m+b+p != 0 {
		t.Fatalf("dados do aluno excluído deveriam ter sumido: medidas=%d bio=%d fotos=%d", m, b, p)
	}
	if m, b, p := counts(tenantID, neighbour); m != 1 || b != 1 || p != 1 {
		t.Fatalf("o outro aluno não pode ser afetado: %d %d %d", m, b, p)
	}
	if m, b, p := counts(otherTenant, student); m != 1 || b != 1 || p != 1 {
		t.Fatalf("o mesmo UUID em outro tenant não pode ser afetado: %d %d %d", m, b, p)
	}
}
