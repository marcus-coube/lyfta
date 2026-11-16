package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/duo/workout/internal/domain"
)

// ErrVariationNameTaken: já existe variação ativa com esse nome no tenant
// (índice único parcial por lower(name), ADR-019).
var ErrVariationNameTaken = errors.New("repo: nome de variação já usado")

// UnknownVariationError: a série aponta para variação que o tenant não
// enxerga, ou arquivada em série nova / que trocou de variação.
type UnknownVariationError struct{ VariationID string }

func (e UnknownVariationError) Error() string {
	return "repo: variação indisponível: " + e.VariationID
}

// Variation é a variação de execução cadastrada pelo tenant (ADR-019).
type Variation struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Description string     `json:"description"`
	ArchivedAt  *time.Time `json:"archived_at"`
	CreatedBy   string     `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

const variationColumns = `id, name, description, archived_at, created_by, created_at, updated_at`

func scanVariation(row pgx.Row) (Variation, error) {
	var v Variation
	err := row.Scan(&v.ID, &v.Name, &v.Description, &v.ArchivedAt, &v.CreatedBy, &v.CreatedAt, &v.UpdatedAt)
	return v, err
}

// VariationRepo dá acesso a set_variations.
type VariationRepo struct{ pool *pgxpool.Pool }

// NewVariationRepo cria o repositório de variações.
func NewVariationRepo(pool *pgxpool.Pool) *VariationRepo { return &VariationRepo{pool: pool} }

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// List devolve as variações do tenant. status: "active" (padrão), "archived"
// ou "all"; q filtra por trecho do nome (sem diferenciar caixa).
func (r *VariationRepo) List(ctx context.Context, tenantID, q, status string) ([]Variation, error) {
	items := []Variation{}
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+variationColumns+` FROM set_variations
			WHERE ($1 = 'all' OR ($1 = 'active' AND archived_at IS NULL) OR ($1 = 'archived' AND archived_at IS NOT NULL))
			  AND ($2 = '' OR name ILIKE '%' || replace(replace(replace($2, '\', '\\'), '%', '\%'), '_', '\_') || '%')
			ORDER BY lower(name), id`, status, q)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			v, err := scanVariation(rows)
			if err != nil {
				return err
			}
			items = append(items, v)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar variações: %w", err)
	}
	return items, nil
}

// Create grava uma variação ativa.
func (r *VariationRepo) Create(ctx context.Context, tenantID, actorID, name, description string) (Variation, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return Variation{}, fmt.Errorf("repo: gerar id da variação: %w", err)
	}
	var v Variation
	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		v, err = scanVariation(tx.QueryRow(ctx, `INSERT INTO set_variations (id, tenant_id, name, description, created_by)
			VALUES ($1, $2, $3, $4, $5) RETURNING `+variationColumns, id.String(), tenantID, name, description, actorID))
		return err
	})
	if isUniqueViolation(err) {
		return Variation{}, ErrVariationNameTaken
	}
	if err != nil {
		return Variation{}, fmt.Errorf("repo: criar variação: %w", err)
	}
	return v, nil
}

// Update troca nome e descrição. Sessões já iniciadas não mudam: o snapshot
// copiou os dois (ADR-004 §2).
func (r *VariationRepo) Update(ctx context.Context, tenantID, id, name, description string) (Variation, error) {
	var v Variation
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		v, err = scanVariation(tx.QueryRow(ctx, `UPDATE set_variations SET name = $2, description = $3, updated_at = now()
			WHERE id = $1 RETURNING `+variationColumns, id, name, description))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Variation{}, ErrNotFound
	}
	if isUniqueViolation(err) {
		return Variation{}, ErrVariationNameTaken
	}
	if err != nil {
		return Variation{}, fmt.Errorf("repo: atualizar variação: %w", err)
	}
	return v, nil
}

// SetArchived arquiva (idempotente) ou reativa. Reativar pode esbarrar no
// nome de outra variação ativa criada nesse meio-tempo.
func (r *VariationRepo) SetArchived(ctx context.Context, tenantID, id string, archived bool) (Variation, error) {
	var v Variation
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var err error
		v, err = scanVariation(tx.QueryRow(ctx, `UPDATE set_variations SET
			archived_at = CASE WHEN $2 THEN COALESCE(archived_at, now()) ELSE NULL END,
			updated_at = CASE WHEN ($2) = (archived_at IS NOT NULL) THEN updated_at ELSE now() END
			WHERE id = $1 RETURNING `+variationColumns, id, archived))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return Variation{}, ErrNotFound
	}
	if isUniqueViolation(err) {
		return Variation{}, ErrVariationNameTaken
	}
	if err != nil {
		return Variation{}, fmt.Errorf("repo: arquivar variação: %w", err)
	}
	return v, nil
}

// assertVariationsUsable valida, sob RLS, as variações da árvore recebida no
// SaveDraft (a FK ignora RLS). Variação inexistente no tenant é sempre
// recusada. Arquivada só passa para as séries que já a usavam: o limite por
// variação é quantas séries da última versão do plano apontam para ela —
// série nova ou que trocou para uma arquivada excede esse número. Cópias de
// árvore (modelo, duplicar) não passam por aqui: copiam o que já existe.
func assertVariationsUsable(ctx context.Context, tx pgx.Tx, planID string, days []domain.Day) error {
	wanted := map[string]int{}
	for _, d := range days {
		for _, b := range d.Blocks {
			for _, be := range b.Exercises {
				for _, s := range be.Sets {
					if s.VariationID != nil {
						wanted[*s.VariationID]++
					}
				}
			}
		}
	}
	if len(wanted) == 0 {
		return nil
	}
	ids := make([]string, 0, len(wanted))
	for id := range wanted {
		ids = append(ids, id)
	}

	archived := map[string]bool{}
	rows, err := tx.Query(ctx, `SELECT id, archived_at IS NOT NULL FROM set_variations WHERE id = ANY($1::uuid[])`, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var isArchived bool
		if err := rows.Scan(&id, &isArchived); err != nil {
			rows.Close()
			return err
		}
		archived[id] = isArchived
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	existing := map[string]int{}
	rows, err = tx.Query(ctx, `
		SELECT ps.variation_id, count(*)
		FROM prescribed_sets ps
		JOIN block_exercises be ON be.id = ps.block_exercise_id
		JOIN workout_blocks b ON b.id = be.block_id
		JOIN workout_days d ON d.id = b.day_id
		WHERE ps.variation_id = ANY($2::uuid[])
		  AND d.plan_version_id = (SELECT id FROM workout_plan_versions
		                           WHERE plan_id = $1 ORDER BY version_no DESC LIMIT 1)
		GROUP BY ps.variation_id`, planID, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			rows.Close()
			return err
		}
		existing[id] = n
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, id := range ids {
		isArchived, found := archived[id]
		if !found || (isArchived && wanted[id] > existing[id]) {
			return UnknownVariationError{VariationID: id}
		}
	}
	return nil
}
