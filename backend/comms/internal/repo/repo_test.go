package repo_test

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// testPool abre um pool contra o Postgres de dev (lyfta_comms, migrations já
// aplicadas). Sem DATABASE_URL configurada explicitamente, usa o mesmo
// default documentado em backend/comms/.env.example. Fora do CI, pula o
// teste se o banco não estiver acessível — mantém `go test ./...` rodável
// sem Postgres.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		// lyfta_app: role sem BYPASSRLS (migration 0006_app_role) — RLS não
		// tem efeito nenhum se o teste conectar como superusuário (postgres).
		dsn = "postgres://lyfta_app:lyfta_app_dev@localhost:5432/lyfta_comms?sslmode=disable"
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
// (Postgres) é obrigatório, e pular deixaria o pipeline verde sem ter testado
// nada (P0.7).
func skipOrFail(t *testing.T, reason string) {
	t.Helper()
	if os.Getenv("CI") != "" {
		t.Fatalf("ambiente incompleto no CI: %s", reason)
	}
	t.Skip(reason)
}

// newID devolve um UUID novo. Não existe tabela de tenants/usuários neste
// banco: tenant, aluno e coach vivem no identity e chegam aqui só como UUID
// (ADR-013 §2).
func newID() string { return uuid.NewString() }

func insertConversation(ctx context.Context, pool *pgxpool.Pool, tenantID, studentID, coachID string) (string, error) {
	id := uuid.NewString()
	err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO conversations (id, tenant_id, student_id, coach_id)
			VALUES ($1, $2, $3, $4)`,
			id, tenantID, studentID, coachID)
		return err
	})
	return id, err
}

func insertMessage(ctx context.Context, pool *pgxpool.Pool, tenantID, conversationID, senderID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO messages (id, tenant_id, conversation_id, sender_id, type, body)
			VALUES ($1, $2, $3, $4, 'text', 'oi')`,
			uuid.NewString(), tenantID, conversationID, senderID)
		return err
	})
}

func insertWorkoutCheckin(ctx context.Context, pool *pgxpool.Pool, tenantID, studentID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO workout_checkins (id, tenant_id, student_id, session_client_id, rating, difficulty)
			VALUES ($1, $2, $3, $4, 4, 3)`,
			uuid.NewString(), tenantID, studentID, uuid.NewString())
		return err
	})
}

func insertDeviceToken(ctx context.Context, pool *pgxpool.Pool, tenantID, userID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO device_tokens (id, tenant_id, user_id, platform, token)
			VALUES ($1, $2, $3, 'android', $4)`,
			uuid.NewString(), tenantID, userID, uuid.NewString())
		return err
	})
}

func insertNotificationLog(ctx context.Context, pool *pgxpool.Pool, tenantID, userID string) error {
	return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO notification_log (id, tenant_id, user_id, kind, payload)
			VALUES ($1, $2, $3, 'message.new', '{}'::jsonb)`,
			uuid.NewString(), tenantID, userID)
		return err
	})
}

// countRows conta as linhas que o tenant informado enxerga na tabela — o RLS
// filtra antes de qualquer contagem chegar ao Go.
func countRows(ctx context.Context, pool *pgxpool.Pool, tenantID, table string) (int, error) {
	var n int
	err := repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, "SELECT count(*) FROM "+table).Scan(&n)
	})
	return n, err
}

// TestCrossTenantIsolation cobre o Aceite da P3.1 e o ADR-001 §6: o tenant B
// não enxerga as conversas, mensagens, check-ins, device tokens nem o log de
// notificação do tenant A, e o próprio tenant A continua enxergando o que
// gravou.
func TestCrossTenantIsolation(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantA, tenantB := newID(), newID()
	studentA, coachA := newID(), newID()

	conversationID, err := insertConversation(ctx, pool, tenantA, studentA, coachA)
	if err != nil {
		t.Fatalf("gravar conversa do A: %v", err)
	}
	if err := insertMessage(ctx, pool, tenantA, conversationID, studentA); err != nil {
		t.Fatalf("gravar mensagem do A: %v", err)
	}
	if err := insertWorkoutCheckin(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar check-in do A: %v", err)
	}
	if err := insertDeviceToken(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar device token do A: %v", err)
	}
	if err := insertNotificationLog(ctx, pool, tenantA, studentA); err != nil {
		t.Fatalf("gravar notification log do A: %v", err)
	}

	for _, table := range []string{"conversations", "messages", "workout_checkins", "device_tokens", "notification_log"} {
		gotA, err := countRows(ctx, pool, tenantA, table)
		if err != nil {
			t.Fatalf("contar %s como A: %v", table, err)
		}
		if gotA != 1 {
			t.Fatalf("%s: A deveria ver o próprio registro, viu %d", table, gotA)
		}

		gotB, err := countRows(ctx, pool, tenantB, table)
		if err != nil {
			t.Fatalf("contar %s como B: %v", table, err)
		}
		if gotB != 0 {
			t.Fatalf("vazamento entre tenants: B viu %d linha(s) de %s do tenant A", gotB, table)
		}
	}
}

// TestRLSBlocksWriteWithoutTenantContext cobre ADR-001 §2: sem
// `app.tenant_id` setado (fora de repo.WithTenant), a policy recusa a
// escrita — a aplicação não pode gravar um fato sem tenant.
func TestRLSBlocksWriteWithoutTenantContext(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newID()

	_, err := pool.Exec(ctx, `
		INSERT INTO device_tokens (id, tenant_id, user_id, platform, token)
		VALUES ($1, $2, $3, 'android', $4)`,
		uuid.NewString(), tenantID, newID(), uuid.NewString())
	if err == nil {
		t.Fatal("insert sem app.tenant_id setado deveria ser recusado pelo RLS")
	}
}

// TestConversationsUniquePerStudentCoach cobre o Aceite da P3.1: "1 conversa
// por par aluno-coach (unique)".
func TestConversationsUniquePerStudentCoach(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID := newID()
	studentID, coachID := newID(), newID()

	if _, err := insertConversation(ctx, pool, tenantID, studentID, coachID); err != nil {
		t.Fatalf("primeira conversa: %v", err)
	}
	if _, err := insertConversation(ctx, pool, tenantID, studentID, coachID); err == nil {
		t.Fatal("segunda conversa para o mesmo par aluno-coach deveria ser recusada")
	}
}

// TestWorkoutCheckinsUniquePerSession cobre a idempotência do P3.3: reenvio
// do check-in da mesma sessão não cria um segundo registro.
func TestWorkoutCheckinsUniquePerSession(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	tenantID, studentID := newID(), newID()
	sessionClientID := uuid.NewString()

	insert := func() error {
		return repo.WithTenant(ctx, pool, tenantID, func(tx pgx.Tx) error {
			_, err := tx.Exec(ctx, `
				INSERT INTO workout_checkins (id, tenant_id, student_id, session_client_id, rating, difficulty)
				VALUES ($1, $2, $3, $4, 5, 2)`,
				uuid.NewString(), tenantID, studentID, sessionClientID)
			return err
		})
	}

	if err := insert(); err != nil {
		t.Fatalf("primeiro check-in: %v", err)
	}
	if err := insert(); err == nil {
		t.Fatal("segundo check-in para o mesmo session_client_id deveria ser recusado")
	}
}
