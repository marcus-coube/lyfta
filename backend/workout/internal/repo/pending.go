package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PendingStudent é um aluno com plano ativo e sem sessão registrada no
// intervalo consultado — o item de GET /internal/v1/pending-students (P3.4).
type PendingStudent struct {
	TenantID  string
	StudentID string
}

// PendingRepo dá acesso à consulta M2M de "treino pendente" (P3.4) — a única
// leitura do serviço sem app.tenant_id: recebe a lista de tenants explícita
// (função SQL SECURITY DEFINER, migrations 0016/0017), então não passa por
// WithTenant como o resto do repositório.
type PendingRepo struct {
	pool *pgxpool.Pool
}

// NewPendingRepo cria um PendingRepo sobre o pool informado.
func NewPendingRepo(pool *pgxpool.Pool) *PendingRepo {
	return &PendingRepo{pool: pool}
}

// PendingStudents devolve, dos tenants pedidos, quem tem plano ativo
// (student_plan_state) e nenhuma sessão com `received_at` dentro de
// [since, until) — o intervalo e os tenants são decididos por quem chama (o
// comms agrupa os tenants por fuso e resolve "hoje" em cada um, P5.1, ver
// backend/comms/internal/job). Lista vazia não devolve ninguém.
func (r *PendingRepo) PendingStudents(ctx context.Context, since, until time.Time, tenantIDs []string) ([]PendingStudent, error) {
	if len(tenantIDs) == 0 {
		return nil, nil
	}
	rows, err := r.pool.Query(ctx, `SELECT tenant_id, student_id FROM find_pending_students($1, $2, $3::uuid[])`, since, until, tenantIDs)
	if err != nil {
		return nil, fmt.Errorf("repo: consultar alunos pendentes: %w", err)
	}
	defer rows.Close()

	var out []PendingStudent
	for rows.Next() {
		var p PendingStudent
		if err := rows.Scan(&p.TenantID, &p.StudentID); err != nil {
			return nil, fmt.Errorf("repo: ler aluno pendente: %w", err)
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("repo: consultar alunos pendentes: %w", err)
	}
	return out, nil
}
