package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// StudentOverview é o resumo de um aluno para listas do coach: quando o
// servidor soube do último treino e qual o plano ativo (nil quando não há).
type StudentOverview struct {
	StudentID     string
	LastSessionAt *time.Time
	ActivePlanID  *string
	ActivePlan    *string
	ActiveVersion *int
}

// OverviewRepo responde o resumo em lote (P5.4).
type OverviewRepo struct {
	pool *pgxpool.Pool
}

// NewOverviewRepo cria um OverviewRepo sobre o pool informado.
func NewOverviewRepo(pool *pgxpool.Pool) *OverviewRepo {
	return &OverviewRepo{pool: pool}
}

// Overviews devolve um item por id pedido, dentro do tenant (RLS). "Último
// treino" é o maior `received_at` das sessões do aluno: o carimbo do servidor
// (ADR-003) é a fonte de verdade — o `started_at` vem do relógio do device —
// e é o mesmo campo que o job de treino pendente usa. O plano ativo é o da
// rotação (student_plan_state), o mesmo critério de GetState/MyPlan.
func (r *OverviewRepo) Overviews(ctx context.Context, tenantID string, studentIDs []string) ([]StudentOverview, error) {
	if len(studentIDs) == 0 {
		return []StudentOverview{}, nil
	}
	out := make([]StudentOverview, 0, len(studentIDs))
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT i.id, ls.last_at, p.id, p.title, v.version_no
			FROM unnest($1::uuid[]) AS i(id)
			LEFT JOIN student_plan_state s ON s.student_id = i.id
			LEFT JOIN workout_plans p ON p.id = s.plan_id
			LEFT JOIN workout_plan_versions v ON v.id = s.active_version_id
			LEFT JOIN LATERAL (
				SELECT MAX(ws.received_at) AS last_at
				FROM workout_sessions ws WHERE ws.student_id = i.id
			) ls ON TRUE`
		rows, err := tx.Query(ctx, q, studentIDs)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var o StudentOverview
			if err := rows.Scan(&o.StudentID, &o.LastSessionAt, &o.ActivePlanID, &o.ActivePlan, &o.ActiveVersion); err != nil {
				return err
			}
			out = append(out, o)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: resumo dos alunos: %w", err)
	}
	return out, nil
}
