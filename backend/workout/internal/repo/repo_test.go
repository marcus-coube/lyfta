package repo_test

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// testPool abre um pool contra o Postgres de dev (lyfta_workout, migrations
// já aplicadas). Sem DATABASE_URL configurada explicitamente, usa o mesmo
// default documentado em backend/workout/.env.example. Fora do CI, pula o
// teste se o banco não estiver acessível — mantém `go test ./...` rodável
// sem Postgres.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		// lyfta_app: role sem BYPASSRLS (migration 0013_app_role) — RLS não
		// tem efeito nenhum se o teste conectar como superusuário (postgres).
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_workout?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := repo.NewPool(ctx, dsn)
	if err != nil {
		// No CI (P0.7) o Postgres é service container obrigatório: pular aqui
		// deixaria o pipeline verde sem ter testado nada.
		skipOrFail(t, "banco indisponível para teste de integração: "+err.Error())
	}
	t.Cleanup(pool.Close)
	return pool
}

// skipOrFail pula o teste fora do CI e falha dentro dele: no CI o ambiente
// (Postgres, seed) é obrigatório, e pular deixaria o pipeline verde sem ter
// testado nada (P0.7).
func skipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// newTenant devolve um tenant_id novo. Não existe tabela de tenants neste
// banco: tenants vivem no identity e chegam aqui só como UUID (ADR-013 §2).
func newTenant() string { return uuid.NewString() }

func intPtr(v int) *int           { return &v }
func floatPtr(v float64) *float64 { return &v }

// seedExercise cria um exercício do tenant para servir de alvo nos blocos.
func seedExercise(t *testing.T, pool *pgxpool.Pool, tenantID string) domain.Exercise {
	t.Helper()
	ex, err := repo.NewExerciseRepo(pool).Create(context.Background(), domain.Exercise{
		TenantID: tenantID, Name: "Supino reto", PrimaryMuscle: "chest",
		Equipment: "barbell", Level: domain.LevelIntermediate,
	}, nil)
	if err != nil {
		t.Fatalf("criar exercício: %v", err)
	}
	return ex
}

// TestPlanTreeRoundTrip cobre o Aceite de P1.1: gravar
// plano → versão → dia → bloco → exercício → sets e ler a árvore de volta com
// a prescrição estruturada intacta (ADR-004 §1, ADR-012 §4).
func TestPlanTreeRoundTrip(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)

	exercise := seedExercise(t, pool, tenantID)

	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: uuid.NewString(), CoachID: uuid.NewString(),
		Title: "Hipertrofia A/B",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	if plan.Status != domain.PlanStatusDraft {
		t.Fatalf("plano deveria nascer em rascunho, veio %q", plan.Status)
	}

	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	if version.VersionNo != 1 {
		t.Fatalf("primeira versão deveria ser 1, veio %d", version.VersionNo)
	}

	day, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0, Title: "Peito e tríceps",
	})
	if err != nil {
		t.Fatalf("criar dia: %v", err)
	}

	block, err := plans.AddBlock(ctx, domain.Block{
		TenantID: tenantID, DayID: day.ID, Position: 0,
		BlockType: domain.BlockTypeSuperset, RestSeconds: 90,
	})
	if err != nil {
		t.Fatalf("criar bloco: %v", err)
	}

	blockExercise, err := plans.AddBlockExercise(ctx, domain.BlockExercise{
		TenantID: tenantID, BlockID: block.ID, ExerciseID: exercise.ID,
		Position: 0, Notes: "cadência controlada",
	})
	if err != nil {
		t.Fatalf("criar exercício do bloco: %v", err)
	}

	rpe := domain.TargetUnitRPE
	for setNo := 1; setNo <= 3; setNo++ {
		if _, err := plans.AddPrescribedSet(ctx, domain.PrescribedSet{
			TenantID: tenantID, BlockExerciseID: blockExercise.ID, SetNo: setNo,
			RepsMin: intPtr(8), RepsMax: intPtr(12), TargetLoadKg: floatPtr(60),
			TargetUnit: &rpe, TargetValue: floatPtr(8), RestSeconds: intPtr(90), Tempo: "3010",
		}); err != nil {
			t.Fatalf("criar set %d: %v", setNo, err)
		}
	}

	// Leitura de volta: a árvore inteira, na ordem das posições.
	days, err := plans.GetVersionTree(ctx, tenantID, version.ID)
	if err != nil {
		t.Fatalf("ler árvore: %v", err)
	}
	if len(days) != 1 {
		t.Fatalf("esperava 1 dia, veio %d", len(days))
	}
	if days[0].Label != "A" || days[0].Title != "Peito e tríceps" {
		t.Fatalf("dia veio errado: %+v", days[0])
	}
	if len(days[0].Blocks) != 1 {
		t.Fatalf("esperava 1 bloco, veio %d", len(days[0].Blocks))
	}
	gotBlock := days[0].Blocks[0]
	if gotBlock.BlockType != domain.BlockTypeSuperset || gotBlock.RestSeconds != 90 {
		t.Fatalf("bloco veio errado: %+v", gotBlock)
	}
	if len(gotBlock.Exercises) != 1 {
		t.Fatalf("esperava 1 exercício no bloco, veio %d", len(gotBlock.Exercises))
	}
	gotExercise := gotBlock.Exercises[0]
	if gotExercise.ExerciseID != exercise.ID || gotExercise.Notes != "cadência controlada" {
		t.Fatalf("exercício do bloco veio errado: %+v", gotExercise)
	}
	if len(gotExercise.Sets) != 3 {
		t.Fatalf("esperava 3 sets, veio %d", len(gotExercise.Sets))
	}
	for i, s := range gotExercise.Sets {
		if s.SetNo != i+1 {
			t.Fatalf("sets fora de ordem: posição %d tem set_no %d", i, s.SetNo)
		}
		if s.RepsMin == nil || *s.RepsMin != 8 || s.RepsMax == nil || *s.RepsMax != 12 {
			t.Fatalf("faixa de reps não sobreviveu ao round-trip: %+v", s)
		}
		if s.TargetLoadKg == nil || *s.TargetLoadKg != 60 {
			t.Fatalf("carga alvo não sobreviveu ao round-trip: %+v", s)
		}
		if s.TargetUnit == nil || *s.TargetUnit != domain.TargetUnitRPE {
			t.Fatalf("unidade do alvo não sobreviveu ao round-trip: %+v", s)
		}
		if s.TargetValue == nil || *s.TargetValue != 8 {
			t.Fatalf("valor do alvo não sobreviveu ao round-trip: %+v", s)
		}
		if s.RestSeconds == nil || *s.RestSeconds != 90 || s.Tempo != "3010" {
			t.Fatalf("descanso/cadência não sobreviveram ao round-trip: %+v", s)
		}
	}
}

// TestCrossTenantIsolation cobre o Aceite de P1.1 e o ADR-001 §6: o tenant B
// não enxerga nada do tenant A, nem o plano nem a árvore nem o exercício.
func TestCrossTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newTenant(), newTenant()
	plans := repo.NewPlanRepo(pool)
	exercises := repo.NewExerciseRepo(pool)

	exerciseA := seedExercise(t, pool, tenantA)
	planA, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantA, StudentID: uuid.NewString(), CoachID: uuid.NewString(), Title: "Plano do A",
	})
	if err != nil {
		t.Fatalf("criar plano do A: %v", err)
	}
	versionA, err := plans.CreateVersion(ctx, tenantA, planA.ID)
	if err != nil {
		t.Fatalf("criar versão do A: %v", err)
	}
	if _, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantA, PlanVersionID: versionA.ID, Label: "A", Position: 0,
	}); err != nil {
		t.Fatalf("criar dia do A: %v", err)
	}

	// B lendo a árvore de A: RLS filtra antes de qualquer join.
	daysForB, err := plans.GetVersionTree(ctx, tenantB, versionA.ID)
	if err != nil {
		t.Fatalf("ler árvore do A como B: %v", err)
	}
	if len(daysForB) != 0 {
		t.Fatalf("vazamento entre tenants: B leu %d dias do plano de A", len(daysForB))
	}

	// B lendo o exercício de A: não é global, então não aparece.
	if _, err := exercises.GetByID(ctx, tenantB, exerciseA.ID); err != repo.ErrNotFound {
		t.Fatalf("vazamento entre tenants: B leu exercício de A (err=%v)", err)
	}

	// A continua enxergando o próprio dado — o isolamento não é "não vê nada".
	daysForA, err := plans.GetVersionTree(ctx, tenantA, versionA.ID)
	if err != nil {
		t.Fatalf("ler árvore do A como A: %v", err)
	}
	if len(daysForA) != 1 {
		t.Fatalf("A deveria ler o próprio dia, veio %d", len(daysForA))
	}
}

// TestGlobalExerciseIsReadOnlyForTenants cobre a policy dupla da 0001
// (ADR-010 §3): o global é legível por qualquer tenant e escrito por nenhum.
func TestGlobalExerciseIsReadOnlyForTenants(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()

	// O seed administrativo do global roda fora da aplicação (superusuário,
	// sem RLS); aqui simulamos apenas o que a role da aplicação consegue fazer.
	err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, execErr := tx.Exec(ctx, `
			INSERT INTO exercises (id, tenant_id, name, primary_muscle, equipment, level, status)
			VALUES ($1, NULL, 'Agachamento global', 'quadríceps', 'barra', 'beginner', 'active')`,
			uuid.NewString())
		return execErr
	})
	if err == nil {
		t.Fatal("a aplicação não pode criar exercício global (tenant_id NULL) — RLS deveria recusar")
	}
}

// TestPublishedVersionIsImmutable cobre ADR-004 §1 no nível do banco: depois
// de publicada, nem a versão nem a árvore abaixo dela aceitam escrita.
func TestPublishedVersionIsImmutable(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)

	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: uuid.NewString(), CoachID: uuid.NewString(), Title: "Plano publicado",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	day, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0,
	})
	if err != nil {
		t.Fatalf("criar dia: %v", err)
	}
	if _, err := plans.Publish(ctx, tenantID, version.ID); err != nil {
		t.Fatalf("publicar versão: %v", err)
	}

	// Editar a árvore de uma versão publicada: recusado pelo trigger.
	if _, err := plans.AddBlock(ctx, domain.Block{
		TenantID: tenantID, DayID: day.ID, Position: 0, BlockType: domain.BlockTypeStraight,
	}); err == nil {
		t.Fatal("bloco novo em versão publicada deveria ser recusado (ADR-004 §1)")
	}
	if _, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "B", Position: 1,
	}); err == nil {
		t.Fatal("dia novo em versão publicada deveria ser recusado (ADR-004 §1)")
	}
	// Republicar (UPDATE na versão) também é recusado.
	if _, err := plans.Publish(ctx, tenantID, version.ID); err == nil {
		t.Fatal("republicar versão já publicada deveria ser recusado (ADR-004 §1)")
	}

	// Uma versão nova continua editável — é assim que o coach edita o plano.
	v2, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar segunda versão: %v", err)
	}
	if v2.VersionNo != 2 {
		t.Fatalf("segunda versão deveria ser 2, veio %d", v2.VersionNo)
	}
	if _, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: v2.ID, Label: "A", Position: 0,
	}); err != nil {
		t.Fatalf("versão em rascunho deveria aceitar edição: %v", err)
	}
}

// TestSetLogsAreAppendOnly cobre ADR-003 §2/§5: log de série executada não é
// editável nem deletável; correção vira outro log com `revises`.
//
// Sem repositório de execução ainda (chega no P1.5), o teste fala SQL direto
// com o banco — o que está sob teste aqui é a garantia do schema.
func TestSetLogsAreAppendOnly(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newTenant()
	plans := repo.NewPlanRepo(pool)

	exercise := seedExercise(t, pool, tenantID)
	plan, err := plans.CreatePlan(ctx, domain.Plan{
		TenantID: tenantID, StudentID: uuid.NewString(), CoachID: uuid.NewString(), Title: "Plano em execução",
	})
	if err != nil {
		t.Fatalf("criar plano: %v", err)
	}
	version, err := plans.CreateVersion(ctx, tenantID, plan.ID)
	if err != nil {
		t.Fatalf("criar versão: %v", err)
	}
	day, err := plans.AddDay(ctx, domain.Day{
		TenantID: tenantID, PlanVersionID: version.ID, Label: "A", Position: 0,
	})
	if err != nil {
		t.Fatalf("criar dia: %v", err)
	}

	sessionID, logID := uuid.NewString(), uuid.NewString()
	clientID := uuid.NewString()
	err = repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			INSERT INTO workout_sessions (id, tenant_id, student_id, plan_version_id, day_id, snapshot, client_id)
			VALUES ($1, $2, $3, $4, $5, '{}'::jsonb, $6)`,
			sessionID, tenantID, uuid.NewString(), version.ID, day.ID, uuid.NewString()); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO workout_set_logs (id, tenant_id, session_id, exercise_id, set_no, reps_done, load_kg, performed_at, client_id)
			VALUES ($1, $2, $3, $4, 1, 10, 60, now(), $5)`,
			logID, tenantID, sessionID, exercise.ID, clientID)
		return err
	})
	if err != nil {
		t.Fatalf("gravar sessão e log: %v", err)
	}

	updateErr := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE workout_set_logs SET load_kg = 70 WHERE id = $1`, logID)
		return err
	})
	if updateErr == nil {
		t.Fatal("UPDATE em workout_set_logs deveria ser recusado (ADR-003 §2)")
	}

	deleteErr := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `DELETE FROM workout_set_logs WHERE id = $1`, logID)
		return err
	})
	if deleteErr == nil {
		t.Fatal("DELETE em workout_set_logs deveria ser recusado (ADR-003 §2)")
	}

	// O caminho correto de correção: novo fato apontando para o revisado.
	reviseErr := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO workout_set_logs (id, tenant_id, session_id, exercise_id, set_no, reps_done, load_kg, performed_at, client_id, revises)
			VALUES ($1, $2, $3, $4, 1, 10, 70, now(), $5, $6)`,
			uuid.NewString(), tenantID, sessionID, exercise.ID, uuid.NewString(), clientID)
		return err
	})
	if reviseErr != nil {
		t.Fatalf("log de revisão deveria ser aceito (ADR-003 §5): %v", reviseErr)
	}
}
