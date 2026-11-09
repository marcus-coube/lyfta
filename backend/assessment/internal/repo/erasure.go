package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErasureRepo apaga o que o serviço guarda de um aluno (P4.5).
type ErasureRepo struct {
	pool *pgxpool.Pool
}

// NewErasureRepo cria um ErasureRepo sobre o pool informado.
func NewErasureRepo(pool *pgxpool.Pool) *ErasureRepo {
	return &ErasureRepo{pool: pool}
}

// EraseUser é a exclusão física (ADR-008 §2: dados de saúde e fotos não se
// anonimizam, se apagam): medidas, bioimpedância, fotos, anamnese e lesões do aluno, numa
// transação. Idempotente. Os objetos das fotos no storage são apagados por
// quem chama (media.Presigner.DeleteStudentObjects).
func (r *ErasureRepo) EraseUser(ctx context.Context, tenantID, studentID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		for _, q := range []string{
			`DELETE FROM body_measurements WHERE student_id = $1`,
			`DELETE FROM bioimpedance_records WHERE student_id = $1`,
			`DELETE FROM progress_photos WHERE student_id = $1`,
			`DELETE FROM student_profiles WHERE student_id = $1`,
			`DELETE FROM student_injuries WHERE student_id = $1`,
		} {
			if _, err := tx.Exec(ctx, q, studentID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: excluir dados do aluno: %w", err)
	}
	return nil
}
