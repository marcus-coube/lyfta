package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TodayRow é o que o workout sabe de um aluno para o painel "hoje" do coach
// (P8.1): se tem plano ativo, o que aconteceu dentro da janela do dia e o
// último treino recebido.
type TodayRow struct {
	StudentID     string
	HasPlan       bool
	SessionsToday int
	FinishedToday bool
	LastSessionAt *time.Time
}

// TodayRepo responde o painel "hoje" em lote.
type TodayRepo struct {
	pool *pgxpool.Pool
}

// NewTodayRepo cria um TodayRepo sobre o pool informado.
func NewTodayRepo(pool *pgxpool.Pool) *TodayRepo {
	return &TodayRepo{pool: pool}
}

// Today devolve uma linha por aluno pedido, dentro do tenant (RLS). A janela
// [since, until) é o dia do tenant, resolvido por quem chama; "hoje" usa
// `received_at` (carimbo do servidor, ADR-003), o mesmo critério do job de
// treino pendente (find_pending_students) e do "último treino" da lista de
// alunos. Plano ativo = linha em student_plan_state.
func (r *TodayRepo) Today(ctx context.Context, tenantID string, studentIDs []string, since, until time.Time) ([]TodayRow, error) {
	out := make([]TodayRow, 0, len(studentIDs))
	if len(studentIDs) == 0 {
		return out, nil
	}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT i.id, s.student_id IS NOT NULL,
			       COALESCE(td.n, 0), COALESCE(td.fin, FALSE), ls.last_at
			FROM unnest($1::uuid[]) AS i(id)
			LEFT JOIN student_plan_state s ON s.student_id = i.id
			LEFT JOIN LATERAL (
				SELECT count(*) AS n, bool_or(ws.finished_at IS NOT NULL) AS fin
				FROM workout_sessions ws
				WHERE ws.student_id = i.id AND ws.received_at >= $2 AND ws.received_at < $3
			) td ON TRUE
			LEFT JOIN LATERAL (
				SELECT MAX(ws.received_at) AS last_at
				FROM workout_sessions ws WHERE ws.student_id = i.id
			) ls ON TRUE`, studentIDs, since, until)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var t TodayRow
			if err := rows.Scan(&t.StudentID, &t.HasPlan, &t.SessionsToday, &t.FinishedToday, &t.LastSessionAt); err != nil {
				return err
			}
			out = append(out, t)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: painel de hoje: %w", err)
	}
	return out, nil
}
