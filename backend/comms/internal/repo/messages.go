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

// maxMessagePageSize é o teto de itens por página do histórico — o cliente
// não decide o tamanho da página sozinho (mesmo critério do assessment).
const maxMessagePageSize = 50

// MessageRepo dá acesso às mensagens (P3.2). Toda operação passa por
// WithTenant (ADR-001 §2).
type MessageRepo struct {
	pool *pgxpool.Pool
}

// NewMessageRepo cria um MessageRepo sobre o pool informado.
func NewMessageRepo(pool *pgxpool.Pool) *MessageRepo {
	return &MessageRepo{pool: pool}
}

// Create grava uma mensagem e atualiza `conversations.last_message_at` na
// mesma transação — sem isso a ordenação de GET /v1/conversations ficaria
// defasada até a próxima leitura.
func (r *MessageRepo) Create(ctx context.Context, m domain.Message) (domain.Message, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Message{}, fmt.Errorf("repo: gerar id da mensagem: %w", err)
	}
	m.ID = id.String()

	err = WithTenant(ctx, r.pool, m.TenantID, func(tx pgx.Tx) error {
		const insertQ = `
			INSERT INTO messages (id, tenant_id, conversation_id, sender_id, type, body, media_key)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING created_at`
		if err := tx.QueryRow(ctx, insertQ,
			m.ID, m.TenantID, m.ConversationID, m.SenderID, string(m.Type), nullString(m.Body), nullString(m.MediaKey),
		).Scan(&m.CreatedAt); err != nil {
			return err
		}

		const touchQ = `UPDATE conversations SET last_message_at = $1 WHERE id = $2`
		_, err := tx.Exec(ctx, touchQ, m.CreatedAt, m.ConversationID)
		return err
	})
	if err != nil {
		return domain.Message{}, fmt.Errorf("repo: criar mensagem: %w", err)
	}
	return m, nil
}

// List devolve o histórico de uma conversa, mais recente primeiro (cursor
// keyset por created_at+id — duas mensagens no mesmo instante não empatam).
func (r *MessageRepo) List(ctx context.Context, tenantID, conversationID string, cursorAt *time.Time, cursorID string, limit int) (items []domain.Message, hasMore bool, err error) {
	if limit <= 0 || limit > maxMessagePageSize {
		limit = maxMessagePageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT id, sender_id, type, COALESCE(body, ''), COALESCE(media_key, ''), created_at, read_at
			FROM messages
			WHERE conversation_id = $1
			  AND ($2::timestamptz IS NULL OR (created_at, id) < ($2::timestamptz, $3::uuid))
			ORDER BY created_at DESC, id DESC
			LIMIT $4`
		rows, queryErr := tx.Query(ctx, q, conversationID, cursorAt, nullString(cursorID), limit+1)
		if queryErr != nil {
			return queryErr
		}
		defer rows.Close()
		for rows.Next() {
			var m domain.Message
			var msgType string
			if err := rows.Scan(&m.ID, &m.SenderID, &msgType, &m.Body, &m.MediaKey, &m.CreatedAt, &m.ReadAt); err != nil {
				return err
			}
			m.TenantID = tenantID
			m.ConversationID = conversationID
			m.Type = domain.MessageType(msgType)
			items = append(items, m)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar mensagens: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// MarkRead marca como lidas as mensagens da conversa não enviadas por
// readerID e ainda sem read_at — devolve os ids marcados (para o handler
// publicar o evento message.read só quando algo mudou de fato).
func (r *MessageRepo) MarkRead(ctx context.Context, tenantID, conversationID, readerID string) ([]string, error) {
	var ids []string
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE messages SET read_at = now()
			WHERE conversation_id = $1 AND sender_id <> $2 AND read_at IS NULL
			RETURNING id`
		rows, err := tx.Query(ctx, q, conversationID, readerID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				return err
			}
			ids = append(ids, id)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: marcar mensagens como lidas: %w", err)
	}
	return ids, nil
}
