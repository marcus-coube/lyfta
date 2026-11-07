package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
)

// maxCheckinPageSize é o teto de itens por página da listagem do coach —
// mesmo critério do maxMessagePageSize.
const maxCheckinPageSize = 50

// checkinCols é a projeção comum às três operações — reviewed_by sai como
// texto (COALESCE para string vazia) porque é uma coluna UUID que pode ser
// NULL; o resto do repositório já resolve nullable assim (ver messages.go).
const checkinCols = `id, student_id, session_client_id, rating, difficulty, pain,
	COALESCE(pain_notes, ''), COALESCE(comment, ''), created_at, COALESCE(reviewed_by::text, ''), reviewed_at`

// CheckinRepo dá acesso aos check-ins de treino (P3.3). Toda operação passa
// por WithTenant (ADR-001 §2).
type CheckinRepo struct {
	pool *pgxpool.Pool
}

// NewCheckinRepo cria um CheckinRepo sobre o pool informado.
func NewCheckinRepo(pool *pgxpool.Pool) *CheckinRepo {
	return &CheckinRepo{pool: pool}
}

func scanCheckin(row pgx.Row, c *domain.WorkoutCheckin) error {
	return row.Scan(
		&c.ID, &c.StudentID, &c.SessionClientID, &c.Rating, &c.Difficulty, &c.Pain,
		&c.PainNotes, &c.Comment, &c.CreatedAt, &c.ReviewedBy, &c.ReviewedAt,
	)
}

// Create grava o check-in do aluno. Idempotente pela unique (tenant_id,
// session_client_id) da migration 0003: reenvio da mesma sessão devolve o
// registro já existente (o ON CONFLICT não atualiza nenhum campo de negócio,
// só re-seleciona a linha) em vez de criar um segundo — mesmo truque do
// ConversationRepo.GetOrCreate.
func (r *CheckinRepo) Create(ctx context.Context, c domain.WorkoutCheckin) (domain.WorkoutCheckin, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.WorkoutCheckin{}, fmt.Errorf("repo: gerar id do check-in: %w", err)
	}
	c.ID = id.String()

	err = WithTenant(ctx, r.pool, c.TenantID, func(tx pgx.Tx) error {
		q := `
			INSERT INTO workout_checkins
				(id, tenant_id, student_id, session_client_id, rating, difficulty, pain, pain_notes, comment)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			ON CONFLICT (tenant_id, session_client_id) DO UPDATE SET tenant_id = workout_checkins.tenant_id
			RETURNING ` + checkinCols
		row := tx.QueryRow(ctx, q,
			c.ID, c.TenantID, c.StudentID, c.SessionClientID, c.Rating, c.Difficulty,
			string(c.Pain), nullString(c.PainNotes), nullString(c.Comment),
		)
		return scanCheckin(row, &c)
	})
	if err != nil {
		return domain.WorkoutCheckin{}, fmt.Errorf("repo: criar check-in: %w", err)
	}
	return c, nil
}

// Get busca um check-in por id, escopado ao tenant. ErrNotFound cobre id
// inexistente e id de outro tenant (RLS já filtrou antes do Go decidir).
func (r *CheckinRepo) Get(ctx context.Context, tenantID, id string) (domain.WorkoutCheckin, error) {
	var c domain.WorkoutCheckin
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `SELECT ` + checkinCols + ` FROM workout_checkins WHERE id = $1`
		return scanCheckin(tx.QueryRow(ctx, q, id), &c)
	})
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.WorkoutCheckin{}, ErrNotFound
		}
		return domain.WorkoutCheckin{}, fmt.Errorf("repo: buscar check-in: %w", err)
	}
	c.TenantID = tenantID
	return c, nil
}

// Review marca o check-in como revisado pelo coach informado — idempotente:
// se já tinha revisão, não sobrescreve quem/quando (a primeira revisão
// vale), só devolve o estado atual.
func (r *CheckinRepo) Review(ctx context.Context, tenantID, id, reviewerID string) (domain.WorkoutCheckin, error) {
	var c domain.WorkoutCheckin
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `
			UPDATE workout_checkins
			SET reviewed_by = COALESCE(reviewed_by, $2), reviewed_at = COALESCE(reviewed_at, now())
			WHERE id = $1
			RETURNING ` + checkinCols
		return scanCheckin(tx.QueryRow(ctx, q, id, reviewerID), &c)
	})
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.WorkoutCheckin{}, ErrNotFound
		}
		return domain.WorkoutCheckin{}, fmt.Errorf("repo: revisar check-in: %w", err)
	}
	c.TenantID = tenantID
	return c, nil
}

// CheckinCursor é o keyset da listagem do coach: mesma ordenação do índice
// idx_workout_checkins_pending (migration 0003) — `reviewed_at NULLS FIRST`
// (não revisados primeiro) e `created_at DESC` como desempate — mais o id
// para desempate final. ReviewedAt vem direto do campo do domínio (nil
// quando o item do cursor não estava revisado) — nada de sentinela artificial
// no lado Go: o SQL já resolve NULL com `COALESCE(reviewed_at, '-infinity')`
// dos dois lados da comparação (linha do banco e valor do cursor), então os
// dois `NULL` sempre caem no mesmo `-infinity` real do Postgres.
type CheckinCursor struct {
	ReviewedAt *time.Time
	CreatedAt  time.Time
	ID         string
}

// NewCheckinCursor monta o cursor a partir do último item de uma página —
// usado pelo handler HTTP para calcular o `next_cursor`.
func NewCheckinCursor(c domain.WorkoutCheckin) CheckinCursor {
	return CheckinCursor{ReviewedAt: c.ReviewedAt, CreatedAt: c.CreatedAt, ID: c.ID}
}

// List devolve os check-ins do tenant — de um aluno específico se studentID
// não for vazio, ou de todos (visão do coach) caso contrário — ordenados com
// os não revisados primeiro e o restante por criação mais recente primeiro
// (Aceite do P3.3). A consulta é escrita em duas variantes (com/sem o filtro
// de aluno) para que o plano sem filtro use só o índice
// idx_workout_checkins_pending — um EXPLAIN confirmou isso (ver Notas de
// execução do P3-comunicacao.md); com o filtro de aluno o Postgres troca
// para idx_workout_checkins_student e ordena em memória, o que é aceitável
// porque o volume por aluno é pequeno.
func (r *CheckinRepo) List(ctx context.Context, tenantID, studentID string, cursor *CheckinCursor, limit int) (items []domain.WorkoutCheckin, hasMore bool, err error) {
	return r.list(ctx, tenantID, studentID, nil, cursor, limit)
}

// ListForStudents é a fila do coach sem owner (ADR-016, P4.7): só os check-ins
// dos alunos do conjunto — `student_id = ANY(...)`. Conjunto vazio devolve
// vazio (e não o tenant inteiro).
func (r *CheckinRepo) ListForStudents(ctx context.Context, tenantID string, studentIDs []string, cursor *CheckinCursor, limit int) (items []domain.WorkoutCheckin, hasMore bool, err error) {
	if studentIDs == nil {
		studentIDs = []string{}
	}
	return r.list(ctx, tenantID, "", studentIDs, cursor, limit)
}

func (r *CheckinRepo) list(ctx context.Context, tenantID, studentID string, studentIDs []string, cursor *CheckinCursor, limit int) (items []domain.WorkoutCheckin, hasMore bool, err error) {
	if limit <= 0 || limit > maxCheckinPageSize {
		limit = maxCheckinPageSize
	}

	// $2 (cursorCreatedAt) NULL sinaliza "sem cursor" (primeira página) — só
	// ele decide isso; $1 (cursorReviewedAt) pode legitimamente ser NULL
	// dentro de um cursor válido (quando o item de referência não estava
	// revisado), por isso os dois lados da comparação passam por COALESCE.
	const cursorPredicate = `
		AND ($2::timestamptz IS NULL OR
			COALESCE(reviewed_at, '-infinity'::timestamptz) > COALESCE($1::timestamptz, '-infinity'::timestamptz) OR
			(COALESCE(reviewed_at, '-infinity'::timestamptz) = COALESCE($1::timestamptz, '-infinity'::timestamptz) AND created_at < $2::timestamptz) OR
			(COALESCE(reviewed_at, '-infinity'::timestamptz) = COALESCE($1::timestamptz, '-infinity'::timestamptz) AND created_at = $2::timestamptz AND id < $3::uuid)
		)`
	const orderAndLimit = `ORDER BY reviewed_at NULLS FIRST, created_at DESC, id DESC LIMIT $4`

	var cursorReviewedAt, cursorCreatedAt *time.Time
	var cursorID string
	if cursor != nil {
		cursorReviewedAt = cursor.ReviewedAt
		createdAt := cursor.CreatedAt
		cursorCreatedAt = &createdAt
		cursorID = cursor.ID
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var q string
		var args []any
		switch {
		case studentIDs != nil:
			q = `SELECT ` + checkinCols + ` FROM workout_checkins WHERE student_id = ANY($5::uuid[]) ` + cursorPredicate + ` ` + orderAndLimit
			args = []any{cursorReviewedAt, cursorCreatedAt, nullString(cursorID), limit + 1, studentIDs}
		case studentID == "":
			q = `SELECT ` + checkinCols + ` FROM workout_checkins WHERE true ` + cursorPredicate + ` ` + orderAndLimit
			args = []any{cursorReviewedAt, cursorCreatedAt, nullString(cursorID), limit + 1}
		default:
			q = `SELECT ` + checkinCols + ` FROM workout_checkins WHERE student_id = $5 ` + cursorPredicate + ` ` + orderAndLimit
			args = []any{cursorReviewedAt, cursorCreatedAt, nullString(cursorID), limit + 1, studentID}
		}

		rows, queryErr := tx.Query(ctx, q, args...)
		if queryErr != nil {
			return queryErr
		}
		defer rows.Close()
		for rows.Next() {
			var c domain.WorkoutCheckin
			if err := scanCheckin(rows, &c); err != nil {
				return err
			}
			c.TenantID = tenantID
			items = append(items, c)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar check-ins: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}
