package repo

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// ExerciseRepo dá acesso à biblioteca de exercícios (ADR-010). Toda operação
// passa por WithTenant: `app.tenant_id` é setado na transação antes de
// qualquer SELECT/INSERT (ADR-001 §2).
type ExerciseRepo struct {
	pool *pgxpool.Pool
}

// NewExerciseRepo cria um ExerciseRepo sobre o pool informado.
func NewExerciseRepo(pool *pgxpool.Pool) *ExerciseRepo {
	return &ExerciseRepo{pool: pool}
}

// DefaultPageSize e MaxPageSize limitam a listagem da biblioteca.
const (
	DefaultPageSize = 30
	MaxPageSize     = 100
)

// exerciseColumns é a projeção comum das leituras de exercício.
const exerciseColumns = `
	e.id, COALESCE(e.tenant_id::text, '') AS tenant_id, e.name, e.primary_muscle,
	e.equipment, e.level, COALESCE(e.media_url, '') AS media_url,
	COALESCE(e.media_type, '') AS media_type,
	COALESCE(e.created_by::text, '') AS created_by, e.status, e.created_at, e.updated_at`

// Create insere um exercício **do tenant** (ADR-010 §3) junto de suas
// traduções, na mesma transação. A biblioteca global (tenant_id NULL) não
// passa por aqui: as policies de escrita da tabela só aceitam linhas do
// próprio tenant, e os globais entram por seed administrativo — tentar criar
// um global pela aplicação falha no RLS, de propósito.
func (r *ExerciseRepo) Create(ctx context.Context, e domain.Exercise, translations []domain.ExerciseTranslation) (domain.Exercise, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: gerar id do exercício: %w", err)
	}
	e.ID = id.String()
	if e.Level == "" {
		e.Level = domain.LevelBeginner
	}
	if e.Status == "" {
		e.Status = domain.ExerciseStatusActive
	}

	err = WithTenant(ctx, r.pool, e.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO exercises (id, tenant_id, name, primary_muscle, equipment, level,
			                       media_url, media_type, created_by, status)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
			RETURNING created_at, updated_at`
		if err := tx.QueryRow(ctx, q,
			e.ID, e.TenantID, e.Name, e.PrimaryMuscle, e.Equipment, string(e.Level),
			nullString(e.MediaURL), nullString(string(e.MediaType)), nullString(e.CreatedBy),
			string(e.Status),
		).Scan(&e.CreatedAt, &e.UpdatedAt); err != nil {
			return err
		}
		return upsertTranslations(ctx, tx, e.TenantID, e.ID, translations)
	})
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: criar exercício: %w", err)
	}
	return e, nil
}

// Update sobrescreve um exercício do tenant e faz upsert das traduções
// enviadas (as não enviadas ficam como estão). Exercício global e de outro
// tenant não são atualizáveis: o RLS não devolve linha e a chamada vira
// ErrNotFound — o handler é quem distingue "não existe" de "é global".
func (r *ExerciseRepo) Update(ctx context.Context, e domain.Exercise, translations []domain.ExerciseTranslation) (domain.Exercise, error) {
	if e.Status == "" {
		e.Status = domain.ExerciseStatusActive
	}
	err := WithTenant(ctx, r.pool, e.TenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE exercises
			SET name = $2, primary_muscle = $3, equipment = $4, level = $5,
			    media_url = $6, media_type = $7, status = $8, updated_at = now()
			WHERE id = $1
			RETURNING created_at, updated_at`
		if err := tx.QueryRow(ctx, q,
			e.ID, e.Name, e.PrimaryMuscle, e.Equipment, string(e.Level),
			nullString(e.MediaURL), nullString(string(e.MediaType)), string(e.Status),
		).Scan(&e.CreatedAt, &e.UpdatedAt); err != nil {
			return err
		}
		return upsertTranslations(ctx, tx, e.TenantID, e.ID, translations)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Exercise{}, ErrNotFound
	}
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: atualizar exercício: %w", err)
	}
	return e, nil
}

// GetByID lê um exercício visível para o tenant — o próprio ou um global
// (policy de leitura dupla da migration 0001).
func (r *ExerciseRepo) GetByID(ctx context.Context, tenantID, exerciseID string) (domain.Exercise, error) {
	var e domain.Exercise
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		q := `SELECT ` + exerciseColumns + ` FROM exercises e WHERE e.id = $1`
		return tx.QueryRow(ctx, q, exerciseID).Scan(
			&e.ID, &e.TenantID, &e.Name, &e.PrimaryMuscle, &e.Equipment, &e.Level,
			&e.MediaURL, &e.MediaType, &e.CreatedBy, &e.Status, &e.CreatedAt, &e.UpdatedAt,
		)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Exercise{}, ErrNotFound
	}
	if err != nil {
		return domain.Exercise{}, fmt.Errorf("repo: buscar exercício: %w", err)
	}
	return e, nil
}

// Translations devolve todas as traduções cadastradas do exercício — o que a
// tela de edição precisa para mostrar os três idiomas lado a lado.
func (r *ExerciseRepo) Translations(ctx context.Context, tenantID, exerciseID string) ([]domain.ExerciseTranslation, error) {
	var out []domain.ExerciseTranslation
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT exercise_id, COALESCE(tenant_id::text, ''), locale, name, instructions
			FROM exercise_translations
			WHERE exercise_id = $1
			ORDER BY locale`
		rows, err := tx.Query(ctx, q, exerciseID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var t domain.ExerciseTranslation
			if err := rows.Scan(&t.ExerciseID, &t.TenantID, &t.Locale, &t.Name, &t.Instructions); err != nil {
				return err
			}
			out = append(out, t)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: traduções do exercício: %w", err)
	}
	return out, nil
}

// List devolve a página da biblioteca visível para o tenant (globais + do
// próprio tenant, pelo RLS), já resolvida no locale pedido.
//
// A ordenação é pelo nome **exibido** normalizado (sem acento, minúsculo) e o
// cursor é keyset sobre (nome normalizado, id): estável mesmo com exercício
// novo entrando no meio da lista, ao contrário de OFFSET. hasMore diz se
// existe página seguinte — a query pede uma linha a mais e ela é descartada.
func (r *ExerciseRepo) List(ctx context.Context, tenantID string, f domain.ExerciseFilter) (items []domain.ExerciseListItem, hasMore bool, err error) {
	limit := f.Limit
	if limit <= 0 {
		limit = DefaultPageSize
	}
	if limit > MaxPageSize {
		limit = MaxPageSize
	}
	locale := f.Locale
	if locale == "" {
		locale = domain.LocaleSource
	}
	chain := make([]string, 0, 3)
	for _, l := range domain.LocaleChain(locale) {
		chain = append(chain, string(l))
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		// A LATERAL pega **uma** tradução por exercício: a primeira da cascata
		// de fallback (array_position sobre a ordem do LocaleChain). Sem
		// tradução nenhuma, COALESCE cai na coluna canônica, que está na
		// língua-fonte (ADR-011 §1).
		const q = `
			WITH resolved AS (
				SELECT ` + exerciseColumns + `,
				       COALESCE(tr.name, e.name) AS display_name,
				       COALESCE(tr.instructions, '') AS instructions,
				       COALESCE(tr.locale, $2) AS name_locale,
				       lyfta_search_norm(COALESCE(tr.name, e.name)) AS sort_key
				FROM exercises e
				LEFT JOIN LATERAL (
					SELECT t.locale, t.name, t.instructions
					FROM exercise_translations t
					WHERE t.exercise_id = e.id AND t.locale = ANY($1::text[])
					ORDER BY array_position($1::text[], t.locale)
					LIMIT 1
				) tr ON TRUE
				WHERE e.status = 'active'
				  AND ($3 = '' OR e.primary_muscle = $3)
				  AND ($4 = '' OR e.equipment = $4)
				  AND ($5 = '' OR e.level = $5)
			)
			SELECT * FROM resolved
			WHERE ($6 = '' OR sort_key LIKE '%' || lyfta_search_norm($6) || '%'
			              OR lyfta_search_norm(name) LIKE '%' || lyfta_search_norm($6) || '%')
			  AND ($7 = '' OR (sort_key, id::text) > ($7, $8))
			ORDER BY sort_key, id::text
			LIMIT $9`

		rows, err := tx.Query(ctx, q,
			chain, string(domain.LocaleSource), f.PrimaryMuscle, f.Equipment, string(f.Level),
			escapeLike(f.Query), f.CursorName, f.CursorID, limit+1,
		)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var it domain.ExerciseListItem
			if err := rows.Scan(
				&it.ID, &it.TenantID, &it.Exercise.Name, &it.PrimaryMuscle, &it.Equipment,
				&it.Level, &it.MediaURL, &it.MediaType, &it.CreatedBy, &it.Status,
				&it.CreatedAt, &it.UpdatedAt,
				&it.DisplayName, &it.Instructions, &it.NameLocale, &it.SortKey,
			); err != nil {
				return err
			}
			items = append(items, it)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: listar exercícios: %w", err)
	}

	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// upsertTranslations grava as traduções do exercício com o tenant espelhado do
// pai — a policy de exercise_translations decide sem join (P1.1).
func upsertTranslations(ctx context.Context, tx pgx.Tx, tenantID, exerciseID string, translations []domain.ExerciseTranslation) error {
	const q = `
		INSERT INTO exercise_translations (exercise_id, tenant_id, locale, name, instructions)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (exercise_id, locale)
		DO UPDATE SET name = EXCLUDED.name, instructions = EXCLUDED.instructions, updated_at = now()`
	for _, t := range translations {
		if _, err := tx.Exec(ctx, q, exerciseID, tenantID, string(t.Locale), t.Name, t.Instructions); err != nil {
			return err
		}
	}
	return nil
}

// escapeLike neutraliza os curingas do LIKE no termo digitado pelo usuário:
// buscar "100%" tem de procurar o texto "100%", não "100" seguido de qualquer
// coisa. A barra invertida é o escape padrão do LIKE no Postgres.
func escapeLike(v string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return replacer.Replace(strings.TrimSpace(v))
}

// nullString converte string vazia em NULL — as colunas opcionais do schema
// (media_url, created_by…) distinguem "sem valor" de string vazia.
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}
