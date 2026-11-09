package repo

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/identity/internal/domain"
)

// UserRepo dá acesso à tabela users e à user_roles associada. Toda operação
// passa por WithTenant para respeitar RLS (ADR-001): `app.tenant_id` é
// setado na transação antes de qualquer SELECT/INSERT.
type UserRepo struct {
	pool *pgxpool.Pool
}

// NewUserRepo cria um UserRepo sobre o pool informado.
func NewUserRepo(pool *pgxpool.Pool) *UserRepo {
	return &UserRepo{pool: pool}
}

// Create insere um usuário e seus papéis dentro do tenant informado,
// respeitando RLS via WithTenant.
func (r *UserRepo) Create(ctx context.Context, u domain.User) (domain.User, error) {
	return r.create(ctx, u, "")
}

// CreateStudent cria o aluno convidado e o vínculo com o professor que o
// convidou na mesma transação: nunca existe aluno sem professor (ADR-016 §1).
func (r *UserRepo) CreateStudent(ctx context.Context, u domain.User, coachID string) (domain.User, error) {
	return r.create(ctx, u, coachID)
}

func (r *UserRepo) create(ctx context.Context, u domain.User, coachID string) (domain.User, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.User{}, fmt.Errorf("repo: gerar id do usuário: %w", err)
	}
	u.ID = id.String()

	err = WithTenant(ctx, r.pool, u.TenantID, func(tx pgx.Tx) error {
		const qUser = `
			INSERT INTO users (id, tenant_id, email, password_hash, name, locale, status)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING created_at`
		if err := tx.QueryRow(ctx, qUser,
			u.ID, u.TenantID, u.Email, u.PasswordHash, u.Name, u.Locale, string(u.Status),
		).Scan(&u.CreatedAt); err != nil {
			return fmt.Errorf("repo: criar usuário: %w", err)
		}

		const qRole = `INSERT INTO user_roles (user_id, tenant_id, role) VALUES ($1, $2, $3)`
		for _, role := range u.Roles {
			if _, err := tx.Exec(ctx, qRole, u.ID, u.TenantID, string(role)); err != nil {
				return fmt.Errorf("repo: atribuir papel %q: %w", role, err)
			}
		}
		if coachID != "" {
			const qLink = `
				INSERT INTO coach_students (tenant_id, student_id, coach_id, assigned_by)
				VALUES ($1, $2, $3, $3)`
			if _, err := tx.Exec(ctx, qLink, u.TenantID, u.ID, coachID); err != nil {
				return fmt.Errorf("repo: vincular aluno ao professor: %w", err)
			}
		}
		return nil
	})
	if err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// FindByEmailInTenant busca um usuário por e-mail dentro do tenant
// informado — RLS garante que não vaza para fora do tenant setado.
func (r *UserRepo) FindByEmailInTenant(ctx context.Context, tenantID, email string) (domain.User, error) {
	var u domain.User
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const qUser = `
			SELECT id, tenant_id, email, password_hash, name, locale, status, created_at
			FROM users WHERE email = $1`
		if err := tx.QueryRow(ctx, qUser, email).Scan(
			&u.ID, &u.TenantID, &u.Email, &u.PasswordHash, &u.Name, &u.Locale, &u.Status, &u.CreatedAt,
		); err != nil {
			if err == pgx.ErrNoRows {
				return ErrNotFound
			}
			return fmt.Errorf("repo: buscar usuário por e-mail: %w", err)
		}

		const qRoles = `SELECT role FROM user_roles WHERE user_id = $1`
		rows, err := tx.Query(ctx, qRoles, u.ID)
		if err != nil {
			return fmt.Errorf("repo: buscar papéis: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			var role string
			if err := rows.Scan(&role); err != nil {
				return fmt.Errorf("repo: ler papel: %w", err)
			}
			u.Roles = append(u.Roles, domain.Role(role))
		}
		return rows.Err()
	})
	if err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// ActivateWithPassword define a senha (já com hash) de um usuário convidado e
// o ativa (status=active) — usado no accept de convite (P0.4).
func (r *UserRepo) ActivateWithPassword(ctx context.Context, tenantID, userID, passwordHash string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE users SET password_hash = $1, status = $2
			WHERE id = $3`
		_, err := tx.Exec(ctx, q, passwordHash, string(domain.UserStatusActive), userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: ativar usuário com senha: %w", err)
	}
	return nil
}

// UpdatePassword troca o hash de senha de um usuário (usado no reset).
func (r *UserRepo) UpdatePassword(ctx context.Context, tenantID, userID, passwordHash string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `UPDATE users SET password_hash = $1 WHERE id = $2`
		_, err := tx.Exec(ctx, q, passwordHash, userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: atualizar senha: %w", err)
	}
	return nil
}

// ListByTenant lista todos os usuários visíveis sob o tenant_id setado —
// usado nos testes de isolamento de RLS.
func (r *UserRepo) ListByTenant(ctx context.Context, tenantID string) ([]domain.User, error) {
	var users []domain.User
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `SELECT id, tenant_id, email, name, locale, status, created_at FROM users ORDER BY created_at`
		rows, err := tx.Query(ctx, q)
		if err != nil {
			return fmt.Errorf("repo: listar usuários: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			var u domain.User
			if err := rows.Scan(&u.ID, &u.TenantID, &u.Email, &u.Name, &u.Locale, &u.Status, &u.CreatedAt); err != nil {
				return fmt.Errorf("repo: ler usuário: %w", err)
			}
			users = append(users, u)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return users, nil
}

// UserFilter são os filtros da listagem de usuários do tenant (P1.6): a tela
// de alunos do professor. Campos vazios não filtram — exceto Status, que vazio
// esconde os inativos (P5.2): quem quer vê-los pede `inactive` de propósito.
type UserFilter struct {
	Role   domain.Role
	Query  string
	Status domain.UserStatus
	// CoachID restringe aos alunos vinculados a esse professor (ADR-016).
	CoachID string
	// Cursor keyset: o nome e o id da última linha da página anterior.
	CursorName string
	CursorID   string
	Limit      int
}

// Tamanhos de página da listagem de usuários.
const (
	DefaultUserPageSize = 50
	MaxUserPageSize     = 200
)

// List devolve a página de usuários do tenant, ordenada por nome. hasMore diz
// se existe página seguinte — a query pede uma linha a mais e a descarta.
//
// A busca cobre nome e e-mail, sem distinguir caixa; o cursor é keyset sobre
// (nome, id), estável quando entra aluno novo no meio da lista.
//
// Status vazio esconde os alunos inativos; `status=inactive` os lista.
func (r *UserRepo) List(ctx context.Context, tenantID string, f UserFilter) (users []domain.User, hasMore bool, err error) {
	limit := f.Limit
	if limit <= 0 {
		limit = DefaultUserPageSize
	}
	if limit > MaxUserPageSize {
		limit = MaxUserPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		// O papel filtra por EXISTS em user_roles: um usuário pode acumular
		// papéis (ADR-002), então um JOIN duplicaria linhas.
		const q = `
			SELECT u.id, u.tenant_id, u.email, u.name, u.locale, u.status, u.created_at,
			       u.phone, u.birth_date::text,
			       COALESCE(
			           (SELECT array_agg(ur.role ORDER BY ur.role)
			            FROM user_roles ur WHERE ur.user_id = u.id),
			           '{}'
			       ) AS roles,
			       cs.coach_id, cu.name
			FROM users u
			LEFT JOIN coach_students cs ON cs.student_id = u.id AND cs.tenant_id = u.tenant_id
			LEFT JOIN users cu ON cu.id = cs.coach_id
			WHERE u.status NOT IN ('deleting', 'deleted')
			  AND ($1::text IS NULL OR EXISTS (
			          SELECT 1 FROM user_roles ur WHERE ur.user_id = u.id AND ur.role = $1))
			  AND (($2::text IS NULL AND u.status <> 'inactive') OR u.status = $2)
			  AND ($3::text IS NULL OR u.name ILIKE $3 OR u.email ILIKE $3)
			  AND ($4::text IS NULL OR (u.name, u.id::text) > ($4, $5))
			  AND ($7::uuid IS NULL OR cs.coach_id = $7)
			ORDER BY u.name, u.id
			LIMIT $6`
		rows, queryErr := tx.Query(ctx, q,
			nullString(string(f.Role)), nullString(string(f.Status)),
			nullString(likePattern(f.Query)), nullString(f.CursorName), f.CursorID, limit+1, nullString(f.CoachID))
		if queryErr != nil {
			return fmt.Errorf("repo: listar usuários: %w", queryErr)
		}
		defer rows.Close()
		for rows.Next() {
			var (
				u     domain.User
				roles []string
			)
			if scanErr := rows.Scan(&u.ID, &u.TenantID, &u.Email, &u.Name, &u.Locale,
				&u.Status, &u.CreatedAt, &u.Phone, &u.BirthDate, &roles, &u.CoachID, &u.CoachName); scanErr != nil {
				return fmt.Errorf("repo: ler usuário: %w", scanErr)
			}
			for _, role := range roles {
				u.Roles = append(u.Roles, domain.Role(role))
			}
			users = append(users, u)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, err
	}
	if len(users) > limit {
		return users[:limit], true, nil
	}
	return users, false, nil
}

// nullString manda NULL em vez de string vazia — é o que deixa os filtros
// opcionais dentro de uma query só.
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

// likePattern monta o padrão de busca escapando os curingas do LIKE, para que
// um nome com `%` não vire busca aberta.
func likePattern(query string) string {
	if query == "" {
		return ""
	}
	escaped := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(query)
	return "%" + escaped + "%"
}

// PasswordHash devolve o hash de senha do usuário — usado só para confirmar a
// senha antes de uma ação destrutiva (exclusão de conta, P4.5).
func (r *UserRepo) PasswordHash(ctx context.Context, tenantID, userID string) (string, error) {
	var hash string
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `SELECT password_hash FROM users WHERE id = $1`, userID).Scan(&hash)
		if err == pgx.ErrNoRows {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		if err == ErrNotFound {
			return "", ErrNotFound
		}
		return "", fmt.Errorf("repo: buscar hash de senha: %w", err)
	}
	return hash, nil
}

// MarkDeleting inicia a exclusão de conta (ADR-008 §2): o usuário passa a
// `deleting` — o login (que só enxerga `active`) e o refresh deixam de
// funcionar — e os refresh tokens são revogados. Idempotente: repetir a
// chamada num usuário já `deleting` é no-op.
func (r *UserRepo) MarkDeleting(ctx context.Context, tenantID, userID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`UPDATE users SET status = 'deleting' WHERE id = $1 AND status IN ('active', 'deleting')`, userID); err != nil {
			return err
		}
		// Coach que sai devolve os alunos ao owner ativo mais antigo: nunca
		// fica aluno sem professor (ADR-016 §1). Para aluno não casa linha.
		if _, err := tx.Exec(ctx, `
			UPDATE coach_students
			SET coach_id = (SELECT o.id FROM users o
			                JOIN user_roles r ON r.user_id = o.id AND r.role = 'owner'
			                WHERE o.status = 'active' ORDER BY o.created_at LIMIT 1),
			    assigned_at = now()
			WHERE coach_id = $1
			  AND EXISTS (SELECT 1 FROM users o
			              JOIN user_roles r ON r.user_id = o.id AND r.role = 'owner'
			              WHERE o.status = 'active')`, userID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx,
			`UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: marcar usuário como deleting: %w", err)
	}
	return nil
}

// Anonymize é o último passo da exclusão (ADR-008 §2): e-mail, nome e hash de
// senha são substituídos, os papéis, tokens, pedidos de reset e convites para
// o e-mail antigo somem, e o usuário vira `deleted`. A linha de `users` fica
// (outros serviços guardam o UUID como pseudônimo, sem como voltar à pessoa) e
// os consentimentos também (prova do que foi concedido, sem dado pessoal).
// Idempotente.
func (r *UserRepo) Anonymize(ctx context.Context, tenantID, userID string) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var email string
		err := tx.QueryRow(ctx, `SELECT email FROM users WHERE id = $1 AND status = 'deleting'`, userID).Scan(&email)
		if err == pgx.ErrNoRows {
			return nil // já anonimizado (ou inexistente): nada a fazer.
		}
		if err != nil {
			return err
		}
		for _, q := range []string{
			`DELETE FROM refresh_tokens WHERE user_id = $1`,
			`DELETE FROM password_resets WHERE user_id = $1`,
			`DELETE FROM user_roles WHERE user_id = $1`,
			`DELETE FROM coach_students WHERE student_id = $1`,
			// `reason` é texto livre e pode citar a pessoa: o histórico sai junto.
			`DELETE FROM user_status_events WHERE user_id = $1`,
		} {
			if _, err := tx.Exec(ctx, q, userID); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(ctx, `DELETE FROM invitations WHERE email = $1`, email); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `
			UPDATE users
			SET email = 'deleted+' || id::text || '@deleted.invalid',
			    name = 'deleted', password_hash = '', status = 'deleted',
			    phone = NULL, birth_date = NULL
			WHERE id = $1`, userID)
		return err
	})
	if err != nil {
		return fmt.Errorf("repo: anonimizar usuário: %w", err)
	}
	return nil
}

// ProfilePatch é a edição parcial do cadastro (P5.2): nil mantém o valor;
// string vazia em Phone/BirthDate apaga o campo.
type ProfilePatch struct {
	Name      *string
	Phone     *string
	BirthDate *string // AAAA-MM-DD
}

// UpdateProfile aplica o patch no usuário (não excluído). ErrNotFound se o id
// não existe no tenant.
func (r *UserRepo) UpdateProfile(ctx context.Context, tenantID, userID string, p ProfilePatch) error {
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE users
			SET name = COALESCE($2, name),
			    phone = CASE WHEN $3::text IS NULL THEN phone ELSE NULLIF($3::text, '') END,
			    birth_date = CASE WHEN $4::text IS NULL THEN birth_date ELSE NULLIF($4::text, '')::date END
			WHERE id = $1 AND status NOT IN ('deleting', 'deleted')`,
			userID, p.Name, p.Phone, p.BirthDate)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err == ErrNotFound {
		return err
	}
	if err != nil {
		return fmt.Errorf("repo: atualizar cadastro: %w", err)
	}
	return nil
}
