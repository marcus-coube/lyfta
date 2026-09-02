package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// PlanRepo grava e lê a árvore do template (ADR-004 §1):
// plano → versão → dia → bloco → exercício do bloco → sets prescritos.
// Escrever em uma versão já publicada é recusado pelo próprio banco
// (triggers da migration 0012), não só por regra de aplicação.
type PlanRepo struct {
	pool *pgxpool.Pool
}

// NewPlanRepo cria um PlanRepo sobre o pool informado.
func NewPlanRepo(pool *pgxpool.Pool) *PlanRepo {
	return &PlanRepo{pool: pool}
}

// CreatePlan cria o template do aluno em rascunho.
func (r *PlanRepo) CreatePlan(ctx context.Context, p domain.Plan) (domain.Plan, error) {
	id, err := newID("plano")
	if err != nil {
		return domain.Plan{}, err
	}
	p.ID = id
	if p.Status == "" {
		p.Status = domain.PlanStatusDraft
	}

	err = WithTenant(ctx, r.pool, p.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_plans (id, tenant_id, student_id, coach_id, title, status)
			VALUES ($1, $2, $3, $4, $5, $6)
			RETURNING created_at, updated_at`
		return tx.QueryRow(ctx, q,
			p.ID, p.TenantID, p.StudentID, p.CoachID, p.Title, string(p.Status),
		).Scan(&p.CreatedAt, &p.UpdatedAt)
	})
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: criar plano: %w", err)
	}
	return p, nil
}

// CreateVersion abre uma versão nova do plano em rascunho (published_at NULL).
// O número da versão é o próximo da sequência do plano.
func (r *PlanRepo) CreateVersion(ctx context.Context, tenantID, planID string) (domain.PlanVersion, error) {
	id, err := newID("versão do plano")
	if err != nil {
		return domain.PlanVersion{}, err
	}
	v := domain.PlanVersion{ID: id, TenantID: tenantID, PlanID: planID}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_plan_versions (id, tenant_id, plan_id, version_no)
			VALUES ($1, $2, $3,
			        (SELECT COALESCE(MAX(version_no), 0) + 1
			         FROM workout_plan_versions WHERE plan_id = $3))
			RETURNING version_no, created_at`
		return tx.QueryRow(ctx, q, v.ID, v.TenantID, v.PlanID).Scan(&v.VersionNo, &v.CreatedAt)
	})
	if err != nil {
		return domain.PlanVersion{}, fmt.Errorf("repo: criar versão do plano: %w", err)
	}
	return v, nil
}

// Publish marca a versão como publicada. É o último UPDATE que a versão
// aceita: dali em diante ela e sua árvore ficam imutáveis (ADR-004 §1).
func (r *PlanRepo) Publish(ctx context.Context, tenantID, versionID string) (time.Time, error) {
	var publishedAt time.Time
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			UPDATE workout_plan_versions SET published_at = now()
			WHERE id = $1
			RETURNING published_at`
		return tx.QueryRow(ctx, q, versionID).Scan(&publishedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrNotFound
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("repo: publicar versão: %w", err)
	}
	return publishedAt, nil
}

// AddDay acrescenta um dia (A/B/C…) à versão.
func (r *PlanRepo) AddDay(ctx context.Context, d domain.Day) (domain.Day, error) {
	id, err := newID("dia")
	if err != nil {
		return domain.Day{}, err
	}
	d.ID = id

	err = WithTenant(ctx, r.pool, d.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_days (id, tenant_id, plan_version_id, label, position, title)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, d.ID, d.TenantID, d.PlanVersionID, d.Label, d.Position, d.Title)
		return execErr
	})
	if err != nil {
		return domain.Day{}, fmt.Errorf("repo: criar dia: %w", err)
	}
	return d, nil
}

// AddBlock acrescenta um bloco ao dia (straight, superset, circuito…).
func (r *PlanRepo) AddBlock(ctx context.Context, b domain.Block) (domain.Block, error) {
	id, err := newID("bloco")
	if err != nil {
		return domain.Block{}, err
	}
	b.ID = id
	if b.BlockType == "" {
		b.BlockType = domain.BlockTypeStraight
	}

	err = WithTenant(ctx, r.pool, b.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO workout_blocks (id, tenant_id, day_id, position, block_type, rest_seconds)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, b.ID, b.TenantID, b.DayID, b.Position, string(b.BlockType), b.RestSeconds)
		return execErr
	})
	if err != nil {
		return domain.Block{}, fmt.Errorf("repo: criar bloco: %w", err)
	}
	return b, nil
}

// AddBlockExercise coloca um exercício numa posição do bloco.
func (r *PlanRepo) AddBlockExercise(ctx context.Context, be domain.BlockExercise) (domain.BlockExercise, error) {
	id, err := newID("exercício do bloco")
	if err != nil {
		return domain.BlockExercise{}, err
	}
	be.ID = id

	err = WithTenant(ctx, r.pool, be.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO block_exercises (id, tenant_id, block_id, exercise_id, position, notes)
			VALUES ($1, $2, $3, $4, $5, $6)`
		_, execErr := tx.Exec(ctx, q, be.ID, be.TenantID, be.BlockID, be.ExerciseID, be.Position, be.Notes)
		return execErr
	})
	if err != nil {
		return domain.BlockExercise{}, fmt.Errorf("repo: criar exercício do bloco: %w", err)
	}
	return be, nil
}

// AddPrescribedSet grava a prescrição estruturada de uma série (ADR-012 §4).
func (r *PlanRepo) AddPrescribedSet(ctx context.Context, s domain.PrescribedSet) (domain.PrescribedSet, error) {
	id, err := newID("set prescrito")
	if err != nil {
		return domain.PrescribedSet{}, err
	}
	s.ID = id

	err = WithTenant(ctx, r.pool, s.TenantID, func(tx pgx.Tx) error {
		const q = `
			INSERT INTO prescribed_sets (id, tenant_id, block_exercise_id, set_no, reps_min, reps_max,
			                             target_load_kg, target_unit, target_value, rest_seconds, tempo)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`
		var unit any
		if s.TargetUnit != nil {
			unit = string(*s.TargetUnit)
		}
		_, execErr := tx.Exec(ctx, q,
			s.ID, s.TenantID, s.BlockExerciseID, s.SetNo, s.RepsMin, s.RepsMax,
			s.TargetLoadKg, unit, s.TargetValue, s.RestSeconds, nullString(s.Tempo),
		)
		return execErr
	})
	if err != nil {
		return domain.PrescribedSet{}, fmt.Errorf("repo: criar set prescrito: %w", err)
	}
	return s, nil
}

// ListDays devolve só o nível dia da versão, em ordem de posição — sem
// blocos, exercícios nem sets.
//
// É o que a rotação precisa (P1.8): a tela Hoje mostra "próximo: B" e oferece
// trocar o treino do dia, e para isso basta rótulo e ordem. Puxar a árvore
// inteira com `GetVersionTree` seria trazer dezenas de sets por uma lista de
// três rótulos.
func (r *PlanRepo) ListDays(ctx context.Context, tenantID, versionID string) ([]domain.Day, error) {
	var days []domain.Day
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, tenant_id, plan_version_id, label, position, title
			FROM workout_days WHERE plan_version_id = $1 ORDER BY position`, versionID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var d domain.Day
			if err := rows.Scan(&d.ID, &d.TenantID, &d.PlanVersionID,
				&d.Label, &d.Position, &d.Title); err != nil {
				return err
			}
			days = append(days, d)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar dias da versão: %w", err)
	}
	return days, nil
}

// GetVersionTree lê a versão inteira montada — dias, blocos, exercícios e
// sets — em uma transação só. É o formato que vira snapshot da sessão
// (ADR-004 §2) e a base da tela de treino do dia.
//
// Uma query por nível, ordenada por posição: a árvore é pequena (um plano tem
// dezenas de linhas, não milhares) e assim cada nível é remontado em memória
// sem o produto cartesiano de um join único.
func (r *PlanRepo) GetVersionTree(ctx context.Context, tenantID, versionID string) ([]domain.Day, error) {
	var days []domain.Day

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		// Os níveis são remontados por **índice**, não por ponteiro para
		// elemento de slice: `append` realoca o array subjacente, e um
		// *domain.Block guardado antes da realocação passaria a apontar para
		// a cópia velha — os sets do primeiro exercício de um bloco com dois
		// exercícios sumiriam da árvore.
		dayIdx := map[string]int{}
		const qDays = `
			SELECT id, tenant_id, plan_version_id, label, position, title
			FROM workout_days WHERE plan_version_id = $1 ORDER BY position`
		rows, err := tx.Query(ctx, qDays, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var d domain.Day
			if err := rows.Scan(&d.ID, &d.TenantID, &d.PlanVersionID, &d.Label, &d.Position, &d.Title); err != nil {
				rows.Close()
				return err
			}
			days = append(days, d)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if len(days) == 0 {
			return nil
		}
		for i := range days {
			dayIdx[days[i].ID] = i
		}

		type blockPos struct{ day, block int }
		blockIdx := map[string]blockPos{}
		const qBlocks = `
			SELECT b.id, b.tenant_id, b.day_id, b.position, b.block_type, b.rest_seconds
			FROM workout_blocks b
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position`
		rows, err = tx.Query(ctx, qBlocks, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var b domain.Block
			if err := rows.Scan(&b.ID, &b.TenantID, &b.DayID, &b.Position, &b.BlockType, &b.RestSeconds); err != nil {
				rows.Close()
				return err
			}
			di := dayIdx[b.DayID]
			days[di].Blocks = append(days[di].Blocks, b)
			blockIdx[b.ID] = blockPos{day: di, block: len(days[di].Blocks) - 1}
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		type exercisePos struct{ day, block, exercise int }
		exerciseIdx := map[string]exercisePos{}
		const qBlockExercises = `
			SELECT be.id, be.tenant_id, be.block_id, be.exercise_id, be.position, be.notes
			FROM block_exercises be
			JOIN workout_blocks b ON b.id = be.block_id
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position, be.position`
		rows, err = tx.Query(ctx, qBlockExercises, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var be domain.BlockExercise
			if err := rows.Scan(&be.ID, &be.TenantID, &be.BlockID, &be.ExerciseID, &be.Position, &be.Notes); err != nil {
				rows.Close()
				return err
			}
			pos := blockIdx[be.BlockID]
			block := &days[pos.day].Blocks[pos.block]
			block.Exercises = append(block.Exercises, be)
			exerciseIdx[be.ID] = exercisePos{day: pos.day, block: pos.block, exercise: len(block.Exercises) - 1}
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		const qSets = `
			SELECT ps.id, ps.tenant_id, ps.block_exercise_id, ps.set_no, ps.reps_min, ps.reps_max,
			       ps.target_load_kg, ps.target_unit, ps.target_value, ps.rest_seconds, COALESCE(ps.tempo, '')
			FROM prescribed_sets ps
			JOIN block_exercises be ON be.id = ps.block_exercise_id
			JOIN workout_blocks b ON b.id = be.block_id
			JOIN workout_days d ON d.id = b.day_id
			WHERE d.plan_version_id = $1
			ORDER BY d.position, b.position, be.position, ps.set_no`
		rows, err = tx.Query(ctx, qSets, versionID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var st domain.PrescribedSet
			if err := rows.Scan(&st.ID, &st.TenantID, &st.BlockExerciseID, &st.SetNo, &st.RepsMin, &st.RepsMax,
				&st.TargetLoadKg, &st.TargetUnit, &st.TargetValue, &st.RestSeconds, &st.Tempo); err != nil {
				rows.Close()
				return err
			}
			pos := exerciseIdx[st.BlockExerciseID]
			be := &days[pos.day].Blocks[pos.block].Exercises[pos.exercise]
			be.Sets = append(be.Sets, st)
		}
		rows.Close()
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: ler árvore da versão: %w", err)
	}
	return days, nil
}

func newID(what string) (string, error) {
	id, err := uuid.NewV7()
	if err != nil {
		return "", fmt.Errorf("repo: gerar id de %s: %w", what, err)
	}
	return id.String(), nil
}

// --- Builder e atribuição (P1.4) ---------------------------------------

// UnknownExerciseError diz que a árvore enviada aponta para um exercício que
// este tenant não enxerga. A FK de block_exercises **não** basta aqui: a
// verificação de chave estrangeira roda com os privilégios do dono da tabela e
// ignora RLS, então um UUID adivinhado de outro tenant passaria por ela.
type UnknownExerciseError struct{ ExerciseID string }

func (e UnknownExerciseError) Error() string {
	return "repo: exercício não visível para o tenant: " + e.ExerciseID
}

// IncompletePlanError aponta o primeiro nível vazio encontrado na versão que
// se tentou publicar (ADR-004 §1: publicar congela; congelar vazio não serve
// para nada). Reason é um código estável, não texto de UI.
type IncompletePlanError struct {
	Reason string // no_days | day_without_block | block_without_exercise | exercise_without_set
	DayID  string
}

func (e IncompletePlanError) Error() string { return "repo: plano incompleto: " + e.Reason }

// ErrNoDraft é devolvido ao publicar um plano que não tem rascunho aberto —
// publicar duas vezes seguidas não gera versão nova.
var ErrNoDraft = errors.New("repo: plano sem rascunho para publicar")

// GetPlan lê o plano do tenant (RLS filtra o resto).
func (r *PlanRepo) GetPlan(ctx context.Context, tenantID, planID string) (domain.Plan, error) {
	var p domain.Plan
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return scanPlan(tx.QueryRow(ctx, `
			SELECT id, tenant_id, student_id, coach_id, title, status, created_at, updated_at
			FROM workout_plans WHERE id = $1`, planID), &p)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Plan{}, ErrNotFound
	}
	if err != nil {
		return domain.Plan{}, fmt.Errorf("repo: buscar plano: %w", err)
	}
	return p, nil
}

// ListPlansByStudent devolve os planos do aluno, mais recentes primeiro, com
// o resumo de versionamento e a marca de qual está ativo.
func (r *PlanRepo) ListPlansByStudent(ctx context.Context, tenantID, studentID string) ([]domain.PlanSummary, error) {
	var out []domain.PlanSummary
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT p.id, p.tenant_id, p.student_id, p.coach_id, p.title, p.status,
			       p.created_at, p.updated_at,
			       COALESCE(v.latest_no, 0), COALESCE(v.published_no, 0), COALESCE(v.has_draft, FALSE),
			       (s.plan_id IS NOT NULL)
			FROM workout_plans p
			LEFT JOIN LATERAL (
				SELECT MAX(version_no) AS latest_no,
				       MAX(version_no) FILTER (WHERE published_at IS NOT NULL) AS published_no,
				       bool_or(published_at IS NULL) AS has_draft
				FROM workout_plan_versions WHERE plan_id = p.id
			) v ON TRUE
			LEFT JOIN student_plan_state s ON s.student_id = p.student_id AND s.plan_id = p.id
			WHERE p.student_id = $1
			ORDER BY p.created_at DESC`
		rows, err := tx.Query(ctx, q, studentID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.PlanSummary
			if err := rows.Scan(&s.ID, &s.TenantID, &s.StudentID, &s.CoachID, &s.Title, &s.Status,
				&s.CreatedAt, &s.UpdatedAt,
				&s.LatestVersionNo, &s.PublishedVersionNo, &s.HasDraft, &s.IsActive); err != nil {
				return err
			}
			out = append(out, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar planos do aluno: %w", err)
	}
	return out, nil
}

// ListVersions devolve as versões do plano, da mais recente para a mais
// antiga — o histórico que a tela do coach mostra ao lado do rascunho.
func (r *PlanRepo) ListVersions(ctx context.Context, tenantID, planID string) ([]domain.PlanVersion, error) {
	var out []domain.PlanVersion
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, tenant_id, plan_id, version_no, published_at, created_at
			FROM workout_plan_versions WHERE plan_id = $1 ORDER BY version_no DESC`, planID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var v domain.PlanVersion
			if err := rows.Scan(&v.ID, &v.TenantID, &v.PlanID, &v.VersionNo, &v.PublishedAt, &v.CreatedAt); err != nil {
				return err
			}
			out = append(out, v)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar versões: %w", err)
	}
	return out, nil
}

// GetState lê a rotação do aluno (ADR-004 §3). ErrNotFound quando o aluno
// ainda não tem plano publicado.
func (r *PlanRepo) GetState(ctx context.Context, tenantID, studentID string) (domain.StudentPlanState, error) {
	var s domain.StudentPlanState
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT tenant_id, student_id, plan_id, active_version_id,
			       next_day_id, last_session_at, updated_at
			FROM student_plan_state WHERE student_id = $1`, studentID).Scan(
			&s.TenantID, &s.StudentID, &s.PlanID, &s.ActiveVersionID,
			&s.NextDayID, &s.LastSessionAt, &s.UpdatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.StudentPlanState{}, ErrNotFound
	}
	if err != nil {
		return domain.StudentPlanState{}, fmt.Errorf("repo: buscar estado do aluno: %w", err)
	}
	return s, nil
}

// ReplaceDraft grava a árvore inteira no rascunho do plano (P1.4): abre um
// rascunho se o plano só tem versões publicadas e substitui o conteúdo do
// rascunho existente caso contrário.
//
// Substituir tudo (DELETE dos dias, que cascateia até os sets, seguido de
// INSERT) em vez de fazer diff de árvore é decisão do plano do MVP: o builder
// envia o estado completo, e um diff correto de cinco níveis com reordenação
// custaria muito mais do que reescrever dezenas de linhas numa transação.
func (r *PlanRepo) ReplaceDraft(ctx context.Context, tenantID, planID, title string, days []domain.Day) (domain.PlanVersion, []domain.Day, error) {
	var version domain.PlanVersion
	saved := make([]domain.Day, 0, len(days))

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		// FOR UPDATE serializa dois coaches salvando o mesmo plano: sem ele,
		// dois DELETE+INSERT concorrentes poderiam intercalar dias.
		var exists string
		if err := tx.QueryRow(ctx, `SELECT id FROM workout_plans WHERE id = $1 FOR UPDATE`, planID).Scan(&exists); err != nil {
			return err
		}
		if title != "" {
			if _, err := tx.Exec(ctx,
				`UPDATE workout_plans SET title = $2, updated_at = now() WHERE id = $1`, planID, title); err != nil {
				return err
			}
		}

		v, err := draftVersionTx(ctx, tx, tenantID, planID)
		if err != nil {
			return err
		}
		version = v

		if _, err := tx.Exec(ctx, `DELETE FROM workout_days WHERE plan_version_id = $1`, version.ID); err != nil {
			return err
		}
		if err := assertExercisesVisible(ctx, tx, days); err != nil {
			return err
		}

		for di := range days {
			day := days[di]
			day.TenantID, day.PlanVersionID, day.Position = tenantID, version.ID, di
			if day.ID, err = newID("dia"); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `
				INSERT INTO workout_days (id, tenant_id, plan_version_id, label, position, title)
				VALUES ($1, $2, $3, $4, $5, $6)`,
				day.ID, day.TenantID, day.PlanVersionID, day.Label, day.Position, day.Title); err != nil {
				return err
			}

			blocks := day.Blocks
			day.Blocks = make([]domain.Block, 0, len(blocks))
			for bi := range blocks {
				block := blocks[bi]
				block.TenantID, block.DayID, block.Position = tenantID, day.ID, bi
				if block.BlockType == "" {
					block.BlockType = domain.BlockTypeStraight
				}
				if block.ID, err = newID("bloco"); err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `
					INSERT INTO workout_blocks (id, tenant_id, day_id, position, block_type, rest_seconds)
					VALUES ($1, $2, $3, $4, $5, $6)`,
					block.ID, block.TenantID, block.DayID, block.Position,
					string(block.BlockType), block.RestSeconds); err != nil {
					return err
				}

				exercises := block.Exercises
				block.Exercises = make([]domain.BlockExercise, 0, len(exercises))
				for ei := range exercises {
					be := exercises[ei]
					be.TenantID, be.BlockID, be.Position = tenantID, block.ID, ei
					if be.ID, err = newID("exercício do bloco"); err != nil {
						return err
					}
					if _, err := tx.Exec(ctx, `
						INSERT INTO block_exercises (id, tenant_id, block_id, exercise_id, position, notes)
						VALUES ($1, $2, $3, $4, $5, $6)`,
						be.ID, be.TenantID, be.BlockID, be.ExerciseID, be.Position, be.Notes); err != nil {
						return err
					}

					sets := be.Sets
					be.Sets = make([]domain.PrescribedSet, 0, len(sets))
					for si := range sets {
						set := sets[si]
						set.TenantID, set.BlockExerciseID, set.SetNo = tenantID, be.ID, si+1
						if set.ID, err = newID("set prescrito"); err != nil {
							return err
						}
						var unit any
						if set.TargetUnit != nil {
							unit = string(*set.TargetUnit)
						}
						if _, err := tx.Exec(ctx, `
							INSERT INTO prescribed_sets (id, tenant_id, block_exercise_id, set_no, reps_min, reps_max,
							                             target_load_kg, target_unit, target_value, rest_seconds, tempo)
							VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
							set.ID, set.TenantID, set.BlockExerciseID, set.SetNo, set.RepsMin, set.RepsMax,
							set.TargetLoadKg, unit, set.TargetValue, set.RestSeconds, nullString(set.Tempo)); err != nil {
							return err
						}
						be.Sets = append(be.Sets, set)
					}
					block.Exercises = append(block.Exercises, be)
				}
				day.Blocks = append(day.Blocks, block)
			}
			saved = append(saved, day)
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.PlanVersion{}, nil, ErrNotFound
	}
	var unknown UnknownExerciseError
	if errors.As(err, &unknown) {
		return domain.PlanVersion{}, nil, err
	}
	if err != nil {
		return domain.PlanVersion{}, nil, fmt.Errorf("repo: gravar rascunho: %w", err)
	}
	return version, saved, nil
}

// PublishDraft congela o rascunho do plano e aponta a rotação do aluno para
// ele (ADR-004 §1 e §3). Tudo numa transação: publicar sem atualizar o estado
// deixaria o aluno lendo a versão anterior.
func (r *PlanRepo) PublishDraft(ctx context.Context, tenantID, planID string) (domain.PlanVersion, domain.StudentPlanState, error) {
	var (
		version domain.PlanVersion
		state   domain.StudentPlanState
	)

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var plan domain.Plan
		if err := scanPlan(tx.QueryRow(ctx, `
			SELECT id, tenant_id, student_id, coach_id, title, status, created_at, updated_at
			FROM workout_plans WHERE id = $1 FOR UPDATE`, planID), &plan); err != nil {
			return err
		}

		if err := tx.QueryRow(ctx, `
			SELECT id, tenant_id, plan_id, version_no, published_at, created_at
			FROM workout_plan_versions
			WHERE plan_id = $1 AND published_at IS NULL
			ORDER BY version_no DESC LIMIT 1`, planID).Scan(
			&version.ID, &version.TenantID, &version.PlanID, &version.VersionNo,
			&version.PublishedAt, &version.CreatedAt); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNoDraft
			}
			return err
		}

		if err := assertVersionComplete(ctx, tx, version.ID); err != nil {
			return err
		}

		if err := tx.QueryRow(ctx, `
			UPDATE workout_plan_versions SET published_at = now() WHERE id = $1
			RETURNING published_at`, version.ID).Scan(&version.PublishedAt); err != nil {
			return err
		}

		nextDayID, err := nextDayForPublish(ctx, tx, plan.StudentID, planID, version.ID)
		if err != nil {
			return err
		}

		// Um plano ativo por aluno: student_plan_state tem uma linha por aluno
		// (PK tenant_id+student_id, P1.1), então publicar um plano novo aposenta
		// o anterior em vez de deixar dois "publicados" na lista do coach.
		if _, err := tx.Exec(ctx, `
			UPDATE workout_plans SET status = 'archived', updated_at = now()
			WHERE student_id = $1 AND id <> $2 AND status = 'published'`, plan.StudentID, planID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE workout_plans SET status = 'published', updated_at = now() WHERE id = $1`, planID); err != nil {
			return err
		}

		return tx.QueryRow(ctx, `
			INSERT INTO student_plan_state (tenant_id, student_id, plan_id, active_version_id, next_day_id)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (tenant_id, student_id) DO UPDATE
			SET plan_id = EXCLUDED.plan_id,
			    active_version_id = EXCLUDED.active_version_id,
			    next_day_id = EXCLUDED.next_day_id,
			    updated_at = now()
			RETURNING tenant_id, student_id, plan_id, active_version_id,
			          next_day_id, last_session_at, updated_at`,
			tenantID, plan.StudentID, planID, version.ID, nullString(nextDayID)).Scan(
			&state.TenantID, &state.StudentID, &state.PlanID, &state.ActiveVersionID,
			&state.NextDayID, &state.LastSessionAt, &state.UpdatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.PlanVersion{}, domain.StudentPlanState{}, ErrNotFound
	}
	var incomplete IncompletePlanError
	if errors.As(err, &incomplete) || errors.Is(err, ErrNoDraft) {
		return domain.PlanVersion{}, domain.StudentPlanState{}, err
	}
	if err != nil {
		return domain.PlanVersion{}, domain.StudentPlanState{}, fmt.Errorf("repo: publicar rascunho: %w", err)
	}
	return version, state, nil
}

// DraftVersion devolve o rascunho aberto do plano, se houver.
func (r *PlanRepo) DraftVersion(ctx context.Context, tenantID, planID string) (domain.PlanVersion, error) {
	return r.versionBy(ctx, tenantID, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions
		WHERE plan_id = $1 AND published_at IS NULL
		ORDER BY version_no DESC LIMIT 1`, planID)
}

// LatestVersion devolve a versão de maior número do plano — o rascunho, se
// existir; a última publicada, caso contrário.
func (r *PlanRepo) LatestVersion(ctx context.Context, tenantID, planID string) (domain.PlanVersion, error) {
	return r.versionBy(ctx, tenantID, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions WHERE plan_id = $1
		ORDER BY version_no DESC LIMIT 1`, planID)
}

// VersionByNo devolve uma versão específica do plano pelo número.
func (r *PlanRepo) VersionByNo(ctx context.Context, tenantID, planID string, versionNo int) (domain.PlanVersion, error) {
	return r.versionBy(ctx, tenantID, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions WHERE plan_id = $1 AND version_no = $2`, planID, versionNo)
}

// GetVersionByID devolve a versão pelo id (usada com o active_version_id do
// estado do aluno).
func (r *PlanRepo) GetVersionByID(ctx context.Context, tenantID, versionID string) (domain.PlanVersion, error) {
	return r.versionBy(ctx, tenantID, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions WHERE id = $1`, versionID)
}

func (r *PlanRepo) versionBy(ctx context.Context, tenantID, query string, args ...any) (domain.PlanVersion, error) {
	var v domain.PlanVersion
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, query, args...).Scan(
			&v.ID, &v.TenantID, &v.PlanID, &v.VersionNo, &v.PublishedAt, &v.CreatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.PlanVersion{}, ErrNotFound
	}
	if err != nil {
		return domain.PlanVersion{}, fmt.Errorf("repo: buscar versão do plano: %w", err)
	}
	return v, nil
}

// draftVersionTx devolve o rascunho aberto do plano ou abre um novo com o
// próximo version_no — é o que faz "editar plano publicado" virar v2.
func draftVersionTx(ctx context.Context, tx pgx.Tx, tenantID, planID string) (domain.PlanVersion, error) {
	var v domain.PlanVersion
	err := tx.QueryRow(ctx, `
		SELECT id, tenant_id, plan_id, version_no, published_at, created_at
		FROM workout_plan_versions
		WHERE plan_id = $1 AND published_at IS NULL
		ORDER BY version_no DESC LIMIT 1`, planID).Scan(
		&v.ID, &v.TenantID, &v.PlanID, &v.VersionNo, &v.PublishedAt, &v.CreatedAt)
	if err == nil {
		return v, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return domain.PlanVersion{}, err
	}

	id, err := newID("versão do plano")
	if err != nil {
		return domain.PlanVersion{}, err
	}
	v = domain.PlanVersion{ID: id, TenantID: tenantID, PlanID: planID}
	err = tx.QueryRow(ctx, `
		INSERT INTO workout_plan_versions (id, tenant_id, plan_id, version_no)
		VALUES ($1, $2, $3,
		        (SELECT COALESCE(MAX(version_no), 0) + 1
		         FROM workout_plan_versions WHERE plan_id = $3))
		RETURNING version_no, created_at`, v.ID, v.TenantID, v.PlanID).Scan(&v.VersionNo, &v.CreatedAt)
	if err != nil {
		return domain.PlanVersion{}, err
	}
	return v, nil
}

// assertExercisesVisible confere, **sob RLS**, que todo exercise_id da árvore
// é global ou do próprio tenant.
func assertExercisesVisible(ctx context.Context, tx pgx.Tx, days []domain.Day) error {
	wanted := map[string]struct{}{}
	for _, d := range days {
		for _, b := range d.Blocks {
			for _, be := range b.Exercises {
				wanted[be.ExerciseID] = struct{}{}
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

	rows, err := tx.Query(ctx, `SELECT id FROM exercises WHERE id = ANY($1::uuid[])`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		delete(wanted, id)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		if _, missing := wanted[id]; missing {
			return UnknownExerciseError{ExerciseID: id}
		}
	}
	return nil
}

// assertVersionComplete recusa publicar versão vazia em qualquer nível
// (`plan_incomplete` do P1.4): sem dia, dia sem bloco, bloco sem exercício ou
// exercício sem set prescrito.
func assertVersionComplete(ctx context.Context, tx pgx.Tx, versionID string) error {
	var days int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM workout_days WHERE plan_version_id = $1`, versionID).Scan(&days); err != nil {
		return err
	}
	if days == 0 {
		return IncompletePlanError{Reason: "no_days"}
	}

	checks := []struct {
		reason string
		query  string
	}{
		{"day_without_block", `
			SELECT d.id FROM workout_days d
			WHERE d.plan_version_id = $1
			  AND NOT EXISTS (SELECT 1 FROM workout_blocks b WHERE b.day_id = d.id)
			ORDER BY d.position LIMIT 1`},
		{"block_without_exercise", `
			SELECT d.id FROM workout_days d
			JOIN workout_blocks b ON b.day_id = d.id
			WHERE d.plan_version_id = $1
			  AND NOT EXISTS (SELECT 1 FROM block_exercises be WHERE be.block_id = b.id)
			ORDER BY d.position, b.position LIMIT 1`},
		{"exercise_without_set", `
			SELECT d.id FROM workout_days d
			JOIN workout_blocks b ON b.day_id = d.id
			JOIN block_exercises be ON be.block_id = b.id
			WHERE d.plan_version_id = $1
			  AND NOT EXISTS (SELECT 1 FROM prescribed_sets ps WHERE ps.block_exercise_id = be.id)
			ORDER BY d.position, b.position, be.position LIMIT 1`},
	}
	for _, check := range checks {
		var dayID string
		err := tx.QueryRow(ctx, check.query, versionID).Scan(&dayID)
		if errors.Is(err, pgx.ErrNoRows) {
			continue
		}
		if err != nil {
			return err
		}
		return IncompletePlanError{Reason: check.reason, DayID: dayID}
	}
	return nil
}

// nextDayForPublish decide para onde a rotação aponta depois do publish: no
// primeiro publish (ou ao trocar de plano) é o primeiro dia; ao republicar o
// mesmo plano, é o dia de **mesmo rótulo** que o aluno ia fazer — republicar
// corrigindo uma carga não pode jogar quem estava no C de volta para o A.
func nextDayForPublish(ctx context.Context, tx pgx.Tx, studentID, planID, versionID string) (string, error) {
	var currentLabel string
	err := tx.QueryRow(ctx, `
		SELECT d.label
		FROM student_plan_state s
		JOIN workout_days d ON d.id = s.next_day_id
		WHERE s.student_id = $1 AND s.plan_id = $2`, studentID, planID).Scan(&currentLabel)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return "", err
	}

	if currentLabel != "" {
		var dayID string
		err := tx.QueryRow(ctx, `
			SELECT id FROM workout_days WHERE plan_version_id = $1 AND label = $2`,
			versionID, currentLabel).Scan(&dayID)
		if err == nil {
			return dayID, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return "", err
		}
	}

	var firstDay string
	err = tx.QueryRow(ctx, `
		SELECT id FROM workout_days WHERE plan_version_id = $1 ORDER BY position LIMIT 1`, versionID).Scan(&firstDay)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return firstDay, nil
}

func scanPlan(row pgx.Row, p *domain.Plan) error {
	return row.Scan(&p.ID, &p.TenantID, &p.StudentID, &p.CoachID, &p.Title, &p.Status, &p.CreatedAt, &p.UpdatedAt)
}

// --- Rotação e sync (P1.5) ---------------------------------------------

// ErrDayNotInPlan diz que o dia pedido no override não pertence à versão
// ativa do aluno. Não é 404 do dia: o dia pode existir de verdade, só não é
// um dia que este aluno pode escolher hoje.
var ErrDayNotInPlan = errors.New("repo: dia não pertence à versão ativa do aluno")

// SetNextDay sobrescreve o próximo dia da rotação (ADR-004 §3: "com override
// manual pelo aluno/coach"). O dia tem de pertencer à versão ativa — apontar
// a rotação para um dia de outro plano deixaria o aluno preso num treino que
// o coach não atribuiu.
func (r *PlanRepo) SetNextDay(ctx context.Context, tenantID, studentID, dayID string) (domain.StudentPlanState, error) {
	var s domain.StudentPlanState

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		var activeVersionID string
		if err := tx.QueryRow(ctx, `
			SELECT active_version_id FROM student_plan_state
			WHERE student_id = $1 FOR UPDATE`, studentID).Scan(&activeVersionID); err != nil {
			return err
		}

		var belongs bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM workout_days WHERE id = $1 AND plan_version_id = $2
			)`, dayID, activeVersionID).Scan(&belongs); err != nil {
			return err
		}
		if !belongs {
			return ErrDayNotInPlan
		}

		return tx.QueryRow(ctx, `
			UPDATE student_plan_state
			SET next_day_id = $2, updated_at = now()
			WHERE student_id = $1
			RETURNING tenant_id, student_id, plan_id, active_version_id,
			          next_day_id, last_session_at, updated_at`, studentID, dayID).Scan(
			&s.TenantID, &s.StudentID, &s.PlanID, &s.ActiveVersionID,
			&s.NextDayID, &s.LastSessionAt, &s.UpdatedAt)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.StudentPlanState{}, ErrNotFound
	}
	if errors.Is(err, ErrDayNotInPlan) {
		return domain.StudentPlanState{}, err
	}
	if err != nil {
		return domain.StudentPlanState{}, fmt.Errorf("repo: sobrescrever próximo dia: %w", err)
	}
	return s, nil
}
