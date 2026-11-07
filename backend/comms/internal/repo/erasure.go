package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// AnonymousUserID é o "autor" das linhas anonimizadas: um UUID nulo que não
// aponta para ninguém (ADR-008 §2).
const AnonymousUserID = "00000000-0000-0000-0000-000000000000"

// ErasureRepo apaga/anonimiza o que o serviço guarda de um usuário (P4.5).
type ErasureRepo struct {
	pool *pgxpool.Pool
}

// NewErasureRepo cria um ErasureRepo sobre o pool informado.
func NewErasureRepo(pool *pgxpool.Pool) *ErasureRepo {
	return &ErasureRepo{pool: pool}
}

// EraseUser trata os dados do usuário (ADR-008 §2), numa transação e de forma
// idempotente:
//   - mensagens: o autor vira o titular anônimo — o histórico continua para o
//     outro participante da conversa, sem apontar para a conta excluída;
//   - check-ins: autor/revisor anônimos e os textos livres (dor, comentário)
//     apagados — são dado de saúde digitado pelo aluno, e as notas numéricas
//     ficam como estatística sem titular;
//   - tokens de push e log de notificações: excluídos.
//
// A conversa em si (o par aluno-coach) permanece: o UUID dela aponta para um
// usuário já anonimizado no identity.
func (r *ErasureRepo) EraseUser(ctx context.Context, tenantID, userID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		for _, q := range []string{
			`UPDATE messages SET sender_id = $2 WHERE sender_id = $1`,
			`UPDATE workout_checkins SET student_id = $2, pain_notes = NULL, comment = NULL WHERE student_id = $1`,
			`UPDATE workout_checkins SET reviewed_by = $2 WHERE reviewed_by = $1`,
		} {
			if _, err := tx.Exec(ctx, q, userID, AnonymousUserID); err != nil {
				return err
			}
		}
		for _, q := range []string{
			`DELETE FROM device_tokens WHERE user_id = $1`,
			`DELETE FROM notification_log WHERE user_id = $1`,
		} {
			if _, err := tx.Exec(ctx, q, userID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("repo: excluir dados do usuário: %w", err)
	}
	return nil
}
