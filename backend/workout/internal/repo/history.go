package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// maxHistoryPageSize é o teto de pontos por página do histórico. O gráfico do
// P2.4 desenha meses de treino, não anos de uma vez.
const maxHistoryPageSize = 100

// ExerciseHistory devolve a série temporal de um exercício para o gráfico de
// progressão (P2.1): um ponto por sessão, do mais recente para o mais antigo.
//
// A agregação é toda em SQL — trazer log a log para somar em Go custaria uma
// linha por série executada na vida do aluno. Logs corrigidos por um
// `set_revision` ficam de fora (`effectiveLogFilter`): o gráfico mostra o que
// aconteceu, não o que foi digitado errado (ADR-003 §5).
//
// A ordem é decrescente porque o cursor é de data e a tela abre no presente; a
// inversão para o eixo do tempo é do cliente. O keyset é o par
// (performed_at, session_id): duas sessões no mesmo instante não empatam.
func (r *SessionRepo) ExerciseHistory(
	ctx context.Context,
	tenantID, studentID, exerciseID string,
	cursorAt time.Time, cursorSessionID string,
	limit int,
) (points []domain.HistoryPoint, hasMore bool, err error) {
	if limit <= 0 || limit > maxHistoryPageSize {
		limit = maxHistoryPageSize
	}

	err = WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			WITH effective AS (
				SELECT l.session_id, l.set_no, l.reps_done, l.load_kg, l.performed_at
				FROM workout_set_logs l
				JOIN workout_sessions s ON s.id = l.session_id
				WHERE s.student_id = $1
				  AND l.exercise_id = $2
				  AND ` + effectiveLogFilter + `
			),
			agg AS (
				SELECT session_id,
				       max(performed_at) AS performed_at,
				       count(*) AS sets,
				       max(load_kg) AS max_load_kg,
				       COALESCE(sum(load_kg * reps_done), 0) AS total_volume_kg
				FROM effective
				GROUP BY session_id
			),
			top AS (
				SELECT DISTINCT ON (session_id) session_id, set_no, reps_done, load_kg
				FROM effective
				ORDER BY session_id, load_kg DESC NULLS LAST, reps_done DESC NULLS LAST, set_no
			)
			SELECT a.session_id, a.performed_at, a.sets, a.max_load_kg, a.total_volume_kg,
			       t.set_no, t.reps_done, t.load_kg
			FROM agg a
			JOIN top t ON t.session_id = a.session_id
			WHERE $3::timestamptz IS NULL
			   OR (a.performed_at, a.session_id) < ($3::timestamptz, $4::uuid)
			ORDER BY a.performed_at DESC, a.session_id DESC
			LIMIT $5`

		var cursorArg any
		if !cursorAt.IsZero() {
			cursorArg = cursorAt
		}
		rows, queryErr := tx.Query(ctx, q, studentID, exerciseID, cursorArg,
			nullString(cursorSessionID), limit+1)
		if queryErr != nil {
			return queryErr
		}
		defer rows.Close()
		for rows.Next() {
			var p domain.HistoryPoint
			if err := rows.Scan(&p.SessionID, &p.PerformedAt, &p.Sets, &p.MaxLoadKg,
				&p.TotalVolumeKg, &p.TopSet.SetNo, &p.TopSet.RepsDone, &p.TopSet.LoadKg); err != nil {
				return err
			}
			points = append(points, p)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, false, fmt.Errorf("repo: histórico do exercício: %w", err)
	}

	if len(points) > limit {
		return points[:limit], true, nil
	}
	return points, false, nil
}

// LoggedExercises lista os exercícios que o aluno já executou, do treinado
// mais recentemente para o mais antigo — é o índice de onde a tela Evolução
// escolhe o que plotar.
//
// Sem paginação de propósito: são os exercícios de uma rotina, dezenas na
// prática, e a tela precisa da lista inteira para o seletor.
func (r *SessionRepo) LoggedExercises(ctx context.Context, tenantID, studentID string) ([]domain.LoggedExercise, error) {
	var out []domain.LoggedExercise

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT l.exercise_id,
			       count(DISTINCT l.session_id) AS sessions,
			       max(l.performed_at) AS last_performed_at
			FROM workout_set_logs l
			JOIN workout_sessions s ON s.id = l.session_id
			WHERE s.student_id = $1
			  AND ` + effectiveLogFilter + `
			GROUP BY l.exercise_id
			ORDER BY last_performed_at DESC`
		rows, err := tx.Query(ctx, q, studentID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var item domain.LoggedExercise
			if err := rows.Scan(&item.ExerciseID, &item.Sessions, &item.LastPerformedAt); err != nil {
				return err
			}
			out = append(out, item)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: exercícios com histórico: %w", err)
	}
	return out, nil
}
