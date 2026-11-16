package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
)

// Retenção da mídia de execução (ADR-020 §3).
const (
	// SessionMediaRetentionUnacked: sem ciência do professor, a mídia some 30
	// dias depois do envio.
	SessionMediaRetentionUnacked = 30 * 24 * time.Hour
	// SessionMediaRetentionAcked: depois da ciência, 7 dias.
	SessionMediaRetentionAcked = 7 * 24 * time.Hour
	// MaxSessionMediaPerSession é o teto de mídias por sessão de treino.
	MaxSessionMediaPerSession = 3
)

const maxSessionMediaPageSize = 50

// ErrSessionMediaLimit: a sessão já tem MaxSessionMediaPerSession mídias.
var ErrSessionMediaLimit = errors.New("repo: limite de mídias por sessão")

// SessionMediaRepo dá acesso à mídia de execução (P12.1). Toda operação passa
// por WithTenant (ADR-001 §2).
type SessionMediaRepo struct {
	pool *pgxpool.Pool
}

// NewSessionMediaRepo cria um SessionMediaRepo sobre o pool informado.
func NewSessionMediaRepo(pool *pgxpool.Pool) *SessionMediaRepo {
	return &SessionMediaRepo{pool: pool}
}

const sessionMediaCols = `id, student_id, session_client_id, COALESCE(exercise_id::text, ''), COALESCE(exercise_name, ''),
	COALESCE(media_key, ''), content_type, size_bytes, COALESCE(note, ''), created_at,
	COALESCE(acked_by::text, ''), acked_at, delete_after, deleted_at`

func scanSessionMedia(row pgx.Row, tenantID string, m *domain.SessionMedia) error {
	m.TenantID = tenantID
	return row.Scan(
		&m.ID, &m.StudentID, &m.SessionClientID, &m.ExerciseID, &m.ExerciseName,
		&m.MediaKey, &m.ContentType, &m.SizeBytes, &m.Note, &m.CreatedAt,
		&m.AckedBy, &m.AckedAt, &m.DeleteAfter, &m.DeletedAt,
	)
}

// Create registra a mídia. Idempotente pela chave do objeto (reenvio devolve
// a linha existente). O limite por sessão é conferido sob um advisory lock
// transacional da sessão, para dois registros simultâneos não furarem o teto.
// Com m.CreatedAt zero o instante é o do banco; delete_after nasce em
// created_at + 30 dias (D5). created=false quando a chave já estava
// registrada.
func (r *SessionMediaRepo) Create(ctx context.Context, m domain.SessionMedia) (out domain.SessionMedia, created bool, err error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.SessionMedia{}, false, fmt.Errorf("repo: gerar id da mídia: %w", err)
	}
	var createdAt any
	if !m.CreatedAt.IsZero() {
		createdAt = m.CreatedAt
	}

	err = WithTenant(ctx, r.pool, m.TenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, m.StudentID+m.SessionClientID); err != nil {
			return err
		}
		existing := tx.QueryRow(ctx, `SELECT `+sessionMediaCols+` FROM session_media WHERE media_key = $1`, m.MediaKey)
		switch err := scanSessionMedia(existing, m.TenantID, &out); {
		case err == nil:
			return nil
		case !errors.Is(err, pgx.ErrNoRows):
			return err
		}

		var n int
		if err := tx.QueryRow(ctx, `
			SELECT count(*) FROM session_media WHERE student_id = $1 AND session_client_id = $2`,
			m.StudentID, m.SessionClientID).Scan(&n); err != nil {
			return err
		}
		if n >= MaxSessionMediaPerSession {
			return ErrSessionMediaLimit
		}

		row := tx.QueryRow(ctx, `
			INSERT INTO session_media
				(id, tenant_id, student_id, session_client_id, exercise_id, exercise_name, media_key,
				 content_type, size_bytes, note, created_at, delete_after)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
				COALESCE($11::timestamptz, now()), COALESCE($11::timestamptz, now()) + make_interval(secs => $12))
			RETURNING `+sessionMediaCols,
			id.String(), m.TenantID, m.StudentID, m.SessionClientID, nullString(m.ExerciseID), nullString(m.ExerciseName),
			m.MediaKey, m.ContentType, m.SizeBytes, nullString(m.Note), createdAt,
			SessionMediaRetentionUnacked.Seconds())
		created = true
		return scanSessionMedia(row, m.TenantID, &out)
	})
	if errors.Is(err, ErrSessionMediaLimit) {
		return domain.SessionMedia{}, false, err
	}
	if err != nil {
		return domain.SessionMedia{}, false, fmt.Errorf("repo: criar mídia de execução: %w", err)
	}
	return out, created, nil
}

// Get busca uma mídia por id no tenant (ErrNotFound cobre inexistente e outro
// tenant — o RLS já filtrou).
func (r *SessionMediaRepo) Get(ctx context.Context, tenantID, id string) (domain.SessionMedia, error) {
	var m domain.SessionMedia
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return scanSessionMedia(tx.QueryRow(ctx, `SELECT `+sessionMediaCols+` FROM session_media WHERE id = $1`, id), tenantID, &m)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.SessionMedia{}, ErrNotFound
	}
	if err != nil {
		return domain.SessionMedia{}, fmt.Errorf("repo: buscar mídia de execução: %w", err)
	}
	return m, nil
}

// ListForSession devolve a mídia do aluno naquela sessão (no máximo 3).
func (r *SessionMediaRepo) ListForSession(ctx context.Context, tenantID, studentID, sessionClientID string) ([]domain.SessionMedia, error) {
	var items []domain.SessionMedia
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT `+sessionMediaCols+` FROM session_media
			WHERE student_id = $1 AND session_client_id = $2
			ORDER BY created_at, id`, studentID, sessionClientID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var m domain.SessionMedia
			if err := scanSessionMedia(rows, tenantID, &m); err != nil {
				return err
			}
			items = append(items, m)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar mídia da sessão: %w", err)
	}
	return items, nil
}

// SessionMediaFilter restringe a listagem do coach: studentID (um aluno),
// studentIDs (conjunto do coach; nil = sem restrição, vazio = nenhum) e
// pendingOnly (sem ciência e ainda não expiradas).
type SessionMediaFilter struct {
	StudentID   string
	StudentIDs  []string
	PendingOnly bool
}

// List pagina por (created_at, id) desc — mais recentes primeiro.
func (r *SessionMediaRepo) List(ctx context.Context, tenantID string, f SessionMediaFilter, cursorAt *time.Time, cursorID string, limit int) (items []domain.SessionMedia, hasMore bool, err error) {
	if limit <= 0 || limit > maxSessionMediaPageSize {
		limit = maxSessionMediaPageSize
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var studentID, studentIDs any
		if f.StudentID != "" {
			studentID = f.StudentID
		}
		if f.StudentIDs != nil {
			studentIDs = f.StudentIDs
		}
		rows, qErr := tx.Query(ctx, `
			SELECT `+sessionMediaCols+` FROM session_media
			WHERE ($1::uuid IS NULL OR student_id = $1)
			  AND ($2::uuid[] IS NULL OR student_id = ANY($2))
			  AND (NOT $3 OR (acked_at IS NULL AND deleted_at IS NULL))
			  AND ($4::timestamptz IS NULL OR (created_at, id) < ($4::timestamptz, $5::uuid))
			ORDER BY created_at DESC, id DESC
			LIMIT $6`, studentID, studentIDs, f.PendingOnly, cursorAt, nullString(cursorID), limit+1)
		if qErr != nil {
			return qErr
		}
		defer rows.Close()
		for rows.Next() {
			var m domain.SessionMedia
			if err := scanSessionMedia(rows, tenantID, &m); err != nil {
				return err
			}
			items = append(items, m)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar mídia de execução: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Ack grava a ciência do professor UMA vez e antecipa a exclusão:
// delete_after = LEAST(delete_after, now + 7 dias). Idempotente: se já houve
// ciência (ou a mídia já expirou), nada muda — repetir não renova o prazo.
// Devolve a linha no estado final.
func (r *SessionMediaRepo) Ack(ctx context.Context, tenantID, id, ackedBy string, now time.Time) (domain.SessionMedia, error) {
	var m domain.SessionMedia
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE session_media
			SET acked_by = $2, acked_at = $3, delete_after = LEAST(delete_after, $3::timestamptz + make_interval(secs => $4))
			WHERE id = $1 AND acked_at IS NULL AND deleted_at IS NULL`,
			id, ackedBy, now, SessionMediaRetentionAcked.Seconds()); err != nil {
			return err
		}
		return scanSessionMedia(tx.QueryRow(ctx, `SELECT `+sessionMediaCols+` FROM session_media WHERE id = $1`, id), tenantID, &m)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.SessionMedia{}, ErrNotFound
	}
	if err != nil {
		return domain.SessionMedia{}, fmt.Errorf("repo: dar ciência da mídia: %w", err)
	}
	return m, nil
}

// Delete remove a linha do aluno (retirada pelo próprio aluno; o objeto já foi
// apagado pelo handler). false = não existe (ou não é dele).
func (r *SessionMediaRepo) Delete(ctx context.Context, tenantID, studentID, id string) (bool, error) {
	var n int64
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM session_media WHERE id = $1 AND student_id = $2`, id, studentID)
		n = tag.RowsAffected()
		return err
	})
	if err != nil {
		return false, fmt.Errorf("repo: apagar mídia de execução: %w", err)
	}
	return n > 0, nil
}

// ListDue devolve as mídias do tenant com prazo vencido e objeto ainda a
// apagar (delete_after <= now, sem deleted_at), a mais antiga primeiro.
func (r *SessionMediaRepo) ListDue(ctx context.Context, tenantID string, now time.Time, limit int) ([]domain.SessionMedia, error) {
	var items []domain.SessionMedia
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT `+sessionMediaCols+` FROM session_media
			WHERE deleted_at IS NULL AND delete_after <= $1
			ORDER BY delete_after, id
			LIMIT $2`, now, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var m domain.SessionMedia
			if err := scanSessionMedia(rows, tenantID, &m); err != nil {
				return err
			}
			items = append(items, m)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar mídia vencida: %w", err)
	}
	return items, nil
}

// MarkDeleted marca a mídia como apagada (objeto já removido do storage): a
// linha fica, sem a chave, para o histórico "mídia expirada".
func (r *SessionMediaRepo) MarkDeleted(ctx context.Context, tenantID, id string, now time.Time) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE session_media SET deleted_at = $2, media_key = NULL WHERE id = $1 AND deleted_at IS NULL`, id, now)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: marcar mídia como apagada: %w", err)
	}
	return nil
}

// CountUnacked conta a mídia sem ciência e ainda não expirada (card do
// dashboard): do tenant inteiro (studentIDs == nil) ou só do conjunto.
func (r *SessionMediaRepo) CountUnacked(ctx context.Context, tenantID string, studentIDs []string) (int, error) {
	var n int
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if studentIDs == nil {
			return tx.QueryRow(ctx, `SELECT count(*) FROM session_media WHERE acked_at IS NULL AND deleted_at IS NULL`).Scan(&n)
		}
		return tx.QueryRow(ctx, `
			SELECT count(*) FROM session_media
			WHERE acked_at IS NULL AND deleted_at IS NULL AND student_id = ANY($1::uuid[])`, studentIDs).Scan(&n)
	})
	if err != nil {
		return 0, fmt.Errorf("repo: contar mídia sem ciência: %w", err)
	}
	return n, nil
}
