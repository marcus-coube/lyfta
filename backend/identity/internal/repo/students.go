package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// StudentRepo cuida do que é só do aluno no identity (P5.2): a ficha de
// cadastro, a mudança de status (inativar/reativar) e o histórico dela. A
// listagem e a edição do cadastro vivem no UserRepo.
type StudentRepo struct {
	pool *pgxpool.Pool
}

// NewStudentRepo cria um StudentRepo sobre o pool informado.
func NewStudentRepo(pool *pgxpool.Pool) *StudentRepo {
	return &StudentRepo{pool: pool}
}

// PendingInvitation é o último convite de aluno ainda não aceito.
type PendingInvitation struct {
	ID        string
	CreatedAt time.Time
	ExpiresAt time.Time
}

// StudentDetail é a ficha do aluno: cadastro, professor, status e convite
// pendente (só quando o aluno ainda está `invited`).
type StudentDetail struct {
	domain.User
	PendingInvitation *PendingInvitation
}

// Get devolve a ficha do aluno, ou ErrNotFound se o id não é de um aluno
// (não excluído) do tenant.
func (r *StudentRepo) Get(ctx context.Context, tenantID, studentID string) (StudentDetail, error) {
	var d StudentDetail
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			SELECT u.id, u.tenant_id, u.email, u.name, u.locale, u.status, u.created_at,
			       u.phone, u.birth_date::text, cs.coach_id, cu.name
			FROM users u
			JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'student'
			LEFT JOIN coach_students cs ON cs.student_id = u.id AND cs.tenant_id = u.tenant_id
			LEFT JOIN users cu ON cu.id = cs.coach_id
			WHERE u.id = $1 AND u.status NOT IN ('deleting', 'deleted')`, studentID).Scan(
			&d.ID, &d.TenantID, &d.Email, &d.Name, &d.Locale, &d.Status, &d.CreatedAt,
			&d.Phone, &d.BirthDate, &d.CoachID, &d.CoachName)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		d.Roles = []domain.Role{domain.RoleStudent}
		if d.Status != domain.UserStatusInvited {
			return nil
		}
		var inv PendingInvitation
		err = tx.QueryRow(ctx, `
			SELECT id, created_at, expires_at FROM invitations
			WHERE email = $1 AND role = 'student' AND accepted_at IS NULL
			ORDER BY created_at DESC LIMIT 1`, d.Email).Scan(&inv.ID, &inv.CreatedAt, &inv.ExpiresAt)
		if err == pgx.ErrNoRows {
			return nil
		}
		if err != nil {
			return err
		}
		d.PendingInvitation = &inv
		return nil
	})
	if err == ErrNotFound {
		return StudentDetail{}, err
	}
	if err != nil {
		return StudentDetail{}, fmt.Errorf("repo: buscar aluno: %w", err)
	}
	return d, nil
}

// SetStatus inativa (active -> inactive) ou reativa (inactive -> active) o
// aluno, grava o evento no histórico e, ao inativar, revoga os refresh tokens
// — o aluno cai do app assim que o access token (15 min) vence e não renova.
// Tudo numa transação, com o usuário travado (FOR UPDATE): duas chamadas
// concorrentes não gravam duas transições iguais.
//
// ErrNotFound: não é aluno do tenant; ErrAlreadyInStatus: já está em `to`;
// ErrInvalidTransition: qualquer outro status de origem.
func (r *StudentRepo) SetStatus(ctx context.Context, tenantID, studentID string, to domain.UserStatus, changedBy, reason string) error {
	from := domain.UserStatusActive
	if to == domain.UserStatusActive {
		from = domain.UserStatusInactive
	}
	eventID, err := uuid.NewV7()
	if err != nil {
		return fmt.Errorf("repo: gerar id do evento: %w", err)
	}
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var current domain.UserStatus
		err := tx.QueryRow(ctx, `
			SELECT u.status FROM users u
			JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'student'
			WHERE u.id = $1 AND u.status NOT IN ('deleting', 'deleted')
			FOR UPDATE OF u`, studentID).Scan(&current)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if current == to {
			return ErrAlreadyInStatus
		}
		if current != from {
			return ErrInvalidTransition
		}
		if _, err := tx.Exec(ctx, `UPDATE users SET status = $2 WHERE id = $1`, studentID, string(to)); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO user_status_events (id, tenant_id, user_id, from_status, to_status, changed_by, reason)
			VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''))`,
			eventID.String(), tenantID, studentID, string(from), string(to), changedBy, reason); err != nil {
			return err
		}
		if to == domain.UserStatusInactive {
			_, err = tx.Exec(ctx,
				`UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, studentID)
		}
		return err
	})
	switch err {
	case nil:
		return nil
	case ErrNotFound, ErrAlreadyInStatus, ErrInvalidTransition:
		return err
	}
	return fmt.Errorf("repo: mudar status do aluno: %w", err)
}

// StatusEvent é uma linha do histórico de status.
type StatusEvent struct {
	From          string
	To            string
	ChangedBy     string
	ChangedByName string
	Reason        *string
	CreatedAt     time.Time
}

// MaxStatusHistory limita o histórico devolvido: são transições feitas à mão,
// um aluno não chega perto disso.
const MaxStatusHistory = 100

// StatusHistory devolve as transições do aluno, da mais recente para a mais
// antiga.
func (r *StudentRepo) StatusHistory(ctx context.Context, tenantID, studentID string) ([]StatusEvent, error) {
	events := []StatusEvent{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT e.from_status, e.to_status, e.changed_by, COALESCE(u.name, ''), e.reason, e.created_at
			FROM user_status_events e
			LEFT JOIN users u ON u.id = e.changed_by
			WHERE e.user_id = $1
			ORDER BY e.created_at DESC, e.id DESC
			LIMIT $2`, studentID, MaxStatusHistory)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var e StatusEvent
			if err := rows.Scan(&e.From, &e.To, &e.ChangedBy, &e.ChangedByName, &e.Reason, &e.CreatedAt); err != nil {
				return err
			}
			events = append(events, e)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: histórico de status: %w", err)
	}
	return events, nil
}

// StatusesOf devolve o status de cada aluno do tenant entre `ids` (M2M, em
// lote). Quem não é aluno não excluído do tenant fica fora do mapa.
func (r *StudentRepo) StatusesOf(ctx context.Context, tenantID string, ids []string) (map[string]domain.UserStatus, error) {
	out := make(map[string]domain.UserStatus, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT u.id, u.status FROM users u
			JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'student'
			WHERE u.id = ANY($1::uuid[]) AND u.status NOT IN ('deleting', 'deleted')`, ids)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			var status domain.UserStatus
			if err := rows.Scan(&id, &status); err != nil {
				return err
			}
			out[id] = status
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: status dos alunos: %w", err)
	}
	return out, nil
}

// StudentStats são os contadores do dashboard (P8.1).
type StudentStats struct {
	Active         int
	Inactive       int
	PendingInvites int
	NewThisMonth   int
}

// Stats conta os alunos do tenant: ativos, inativos, convidados que ainda não
// aceitaram e criados a partir de `monthStart` (início do mês no fuso do
// tenant). `coachID` != "" restringe aos alunos vinculados a esse professor.
// Excluídos (deleting/deleted) ficam fora de tudo.
func (r *StudentRepo) Stats(ctx context.Context, tenantID, coachID string, monthStart time.Time) (StudentStats, error) {
	var s StudentStats
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT
			  count(*) FILTER (WHERE u.status = 'active'),
			  count(*) FILTER (WHERE u.status = 'inactive'),
			  count(*) FILTER (WHERE u.status = 'invited'),
			  count(*) FILTER (WHERE u.created_at >= $2)
			FROM users u
			JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'student'
			WHERE u.status NOT IN ('deleting', 'deleted')
			  AND ($1 = '' OR EXISTS (
			    SELECT 1 FROM coach_students cs
			    WHERE cs.student_id = u.id AND cs.tenant_id = u.tenant_id AND cs.coach_id::text = $1))`,
			coachID, monthStart).Scan(&s.Active, &s.Inactive, &s.PendingInvites, &s.NewThisMonth)
	})
	if err != nil {
		return StudentStats{}, fmt.Errorf("repo: estatísticas de alunos: %w", err)
	}
	return s, nil
}

// ActiveIDs devolve os ids dos alunos `active` do tenant (M2M do dashboard,
// P8.1: o owner sem filtro de professor).
func (r *StudentRepo) ActiveIDs(ctx context.Context, tenantID string) ([]string, error) {
	ids := []string{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT u.id::text FROM users u
			JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'student'
			WHERE u.status = 'active' ORDER BY u.id`)
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
		return nil, fmt.Errorf("repo: alunos ativos: %w", err)
	}
	return ids, nil
}
