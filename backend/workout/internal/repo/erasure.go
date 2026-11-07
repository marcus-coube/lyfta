package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// AnonymousUserID é o "titular" das linhas anonimizadas: um UUID nulo que não
// aponta para ninguém (ADR-008 §2: execuções viram estatística sem titular).
const AnonymousUserID = "00000000-0000-0000-0000-000000000000"

// ErasureRepo apaga/anonimiza o que o serviço guarda de um usuário (P4.5).
type ErasureRepo struct {
	pool *pgxpool.Pool
}

// NewErasureRepo cria um ErasureRepo sobre o pool informado.
func NewErasureRepo(pool *pgxpool.Pool) *ErasureRepo {
	return &ErasureRepo{pool: pool}
}

// EraseUser trata os dados do usuário como aluno (ADR-008 §2), numa transação
// e de forma idempotente:
//   - execuções (sessões e, por consequência, os logs de série): o aluno vira
//     o titular anônimo — os fatos continuam, sem dono. Os logs são
//     append-only (ADR-003) e nem são tocados: só apontam para a sessão;
//   - estado de rotação do aluno: excluído;
//   - planos atribuídos: desatribuídos (student_id anônimo, título limpo), não
//     deletados — a versão publicada é imutável (ADR-004 §1) e as sessões
//     anonimizadas ainda referenciam o snapshot dela. Desatribuído, o plano
//     deixa de aparecer para qualquer pessoa.
func (r *ErasureRepo) EraseUser(ctx context.Context, tenantID, userID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		for _, q := range []string{
			`UPDATE workout_sessions SET student_id = $2 WHERE student_id = $1`,
			`UPDATE workout_plans SET student_id = $2, title = '' WHERE student_id = $1`,
		} {
			if _, err := tx.Exec(ctx, q, userID, AnonymousUserID); err != nil {
				return err
			}
		}
		_, err := tx.Exec(ctx, `DELETE FROM student_plan_state WHERE student_id = $1`, userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: excluir dados do usuário: %w", err)
	}
	return nil
}
