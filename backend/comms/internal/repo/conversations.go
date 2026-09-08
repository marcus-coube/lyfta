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

// ConversationRepo dá acesso às conversas (P3.2). Toda operação passa por
// WithTenant: `app.tenant_id` é setado na transação antes de qualquer
// SELECT/INSERT (ADR-001 §2).
type ConversationRepo struct {
	pool *pgxpool.Pool
}

// NewConversationRepo cria um ConversationRepo sobre o pool informado.
func NewConversationRepo(pool *pgxpool.Pool) *ConversationRepo {
	return &ConversationRepo{pool: pool}
}

// GetOrCreate devolve a conversa do par (studentID, coachID), criando-a se
// ainda não existir. Idempotente pela unique (tenant_id, student_id,
// coach_id) da migration 0001 — corrida entre duas chamadas simultâneas
// resolve pelo ON CONFLICT, sem exigir lock explícito.
func (r *ConversationRepo) GetOrCreate(ctx context.Context, tenantID, studentID, coachID string) (domain.Conversation, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Conversation{}, fmt.Errorf("repo: gerar id da conversa: %w", err)
	}

	var c domain.Conversation
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO conversations (id, tenant_id, student_id, coach_id)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (tenant_id, student_id, coach_id) DO UPDATE SET tenant_id = conversations.tenant_id
			RETURNING id, student_id, coach_id, created_at, last_message_at`
		return tx.QueryRow(ctx, q, id.String(), tenantID, studentID, coachID).
			Scan(&c.ID, &c.StudentID, &c.CoachID, &c.CreatedAt, &c.LastMessageAt)
	})
	if err != nil {
		return domain.Conversation{}, fmt.Errorf("repo: get-or-create conversa: %w", err)
	}
	c.TenantID = tenantID
	return c, nil
}

// Get busca uma conversa por id, escopada ao tenant. ErrNotFound cobre id
// inexistente e id de outro tenant (RLS já filtrou antes do Go decidir).
func (r *ConversationRepo) Get(ctx context.Context, tenantID, id string) (domain.Conversation, error) {
	var c domain.Conversation
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `SELECT id, student_id, coach_id, created_at, last_message_at FROM conversations WHERE id = $1`
		return tx.QueryRow(ctx, q, id).Scan(&c.ID, &c.StudentID, &c.CoachID, &c.CreatedAt, &c.LastMessageAt)
	})
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.Conversation{}, ErrNotFound
		}
		return domain.Conversation{}, fmt.Errorf("repo: buscar conversa: %w", err)
	}
	c.TenantID = tenantID
	return c, nil
}

// ListForUser lista as conversas em que userID é aluno ou coach, mais
// recentemente ativas primeiro (sem conversa nenhuma primeiro fica para
// último — nulls last), com a prévia da última mensagem e o contador de não
// lidas do ponto de vista de userID (mensagens de quem não é userID e ainda
// sem read_at).
func (r *ConversationRepo) ListForUser(ctx context.Context, tenantID, userID string) ([]domain.ConversationSummary, error) {
	var items []domain.ConversationSummary
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT
				c.id, c.student_id, c.coach_id, c.created_at, c.last_message_at,
				lm.id, lm.sender_id, lm.type, COALESCE(lm.body, ''), COALESCE(lm.media_key, ''), lm.created_at, lm.read_at,
				COALESCE((
					SELECT count(*) FROM messages m
					WHERE m.conversation_id = c.id AND m.sender_id <> $1 AND m.read_at IS NULL
				), 0) AS unread_count
			FROM conversations c
			LEFT JOIN LATERAL (
				SELECT id, sender_id, type, body, media_key, created_at, read_at
				FROM messages
				WHERE conversation_id = c.id
				ORDER BY created_at DESC, id DESC
				LIMIT 1
			) lm ON true
			WHERE c.student_id = $1 OR c.coach_id = $1
			ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC`
		rows, err := tx.Query(ctx, q, userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.ConversationSummary
			var lmID, lmSender, lmType *string
			var lmBody, lmMediaKey string
			var lmCreatedAt, lmReadAt *time.Time
			if err := rows.Scan(
				&s.ID, &s.StudentID, &s.CoachID, &s.CreatedAt, &s.LastMessageAt,
				&lmID, &lmSender, &lmType, &lmBody, &lmMediaKey, &lmCreatedAt, &lmReadAt,
				&s.UnreadCount,
			); err != nil {
				return err
			}
			s.TenantID = tenantID
			if lmID != nil {
				s.LastMessage = &domain.Message{
					ID: *lmID, TenantID: tenantID, ConversationID: s.ID, SenderID: *lmSender,
					Type: domain.MessageType(*lmType), Body: lmBody, MediaKey: lmMediaKey,
					ReadAt: lmReadAt,
				}
				if lmCreatedAt != nil {
					s.LastMessage.CreatedAt = *lmCreatedAt
				}
			}
			items = append(items, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar conversas: %w", err)
	}
	return items, nil
}
