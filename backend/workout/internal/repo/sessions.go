package repo

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

// SessionRepo é o lado servidor do contrato offline (ADR-003): recebe a fila
// de eventos do device, grava a execução append-only e responde as leituras
// da tela Hoje (carga anterior e histórico recente).
type SessionRepo struct {
	pool *pgxpool.Pool
}

// NewSessionRepo cria um SessionRepo sobre o pool informado.
func NewSessionRepo(pool *pgxpool.Pool) *SessionRepo {
	return &SessionRepo{pool: pool}
}

// Códigos de rejeição de evento. São estáveis: o app os guarda na fila local
// para decidir entre descartar o evento e mostrar erro ao aluno.
const (
	RejectUnknownDay        = "unknown_day"
	RejectUnknownSession    = "unknown_session"
	RejectUnknownExercise   = "unknown_exercise"
	RejectUnknownRevisedLog = "unknown_revised_log"
)

// maxRecentSessions é o tamanho do histórico que a tela Hoje mostra.
const maxRecentSessions = 3

// effectiveLogFilter descarta o log que já foi corrigido por um
// `set_revision` (ADR-003 §5): o fato antigo continua na tabela — ele é
// imutável —, mas some das leituras.
const effectiveLogFilter = `
	NOT EXISTS (SELECT 1 FROM workout_set_logs rev WHERE rev.revises = l.client_id)`

// ApplyEvents drena um lote da fila offline em uma transação, evento a evento
// e na ordem recebida (ADR-003 §4).
//
// Cada evento roda dentro do seu **savepoint**: um evento rejeitado (dia que
// não existe, sessão desconhecida) desfaz só a si mesmo e o resto do lote
// segue. Sem isso, o primeiro erro abortaria a transação inteira e o device
// nunca conseguiria drenar a fila — ficaria reenviando o mesmo lote para
// sempre.
//
// studentID vem sempre da claim: um token só empurra a própria execução.
func (r *SessionRepo) ApplyEvents(ctx context.Context, tenantID, studentID string, events []domain.SyncEvent) ([]domain.SyncResult, error) {
	results := make([]domain.SyncResult, 0, len(events))

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		for _, ev := range events {
			sp, err := tx.Begin(ctx)
			if err != nil {
				return err
			}
			res, err := applyEvent(ctx, sp, tenantID, studentID, ev)
			if err != nil {
				_ = sp.Rollback(ctx)
				return err
			}
			if res.Status == domain.SyncStatusRejected {
				// Rejeição desfaz o que o evento tocou (e limpa a transação
				// se o motivo veio de um erro do banco).
				_ = sp.Rollback(ctx)
			} else if err := sp.Commit(ctx); err != nil {
				return err
			}
			results = append(results, res)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("repo: aplicar lote de sync: %w", err)
	}
	return results, nil
}

// applyEvent despacha um evento da fila. Erro devolvido é falha de infra (o
// lote inteiro aborta); rejeição de negócio volta dentro do SyncResult.
func applyEvent(ctx context.Context, tx pgx.Tx, tenantID, studentID string, ev domain.SyncEvent) (domain.SyncResult, error) {
	res := domain.SyncResult{ClientID: ev.ClientID}
	switch ev.Type {
	case domain.SyncEventSessionStart:
		return startSession(ctx, tx, tenantID, studentID, ev)
	case domain.SyncEventSetLog, domain.SyncEventSetRevision:
		return logSet(ctx, tx, tenantID, studentID, ev)
	case domain.SyncEventSessionFinish:
		return finishSession(ctx, tx, studentID, ev)
	default:
		// O handler já validou o tipo; aqui é só para o switch ser total.
		res.Status = domain.SyncStatusRejected
		res.Code = "unknown_event_type"
		return res, nil
	}
}

// startSession congela o snapshot do dia e abre a sessão (ADR-004 §2).
//
// O snapshot é montado **no servidor**, a partir da versão publicada, e não
// copiado do que o device mandou: o histórico do aluno não pode depender do
// que um cliente afirma que estava na tela.
func startSession(ctx context.Context, tx pgx.Tx, tenantID, studentID string, ev domain.SyncEvent) (domain.SyncResult, error) {
	res := domain.SyncResult{ClientID: ev.ClientID}

	var (
		planVersionID string
		snapshot      []byte
	)
	err := tx.QueryRow(ctx, daySnapshotQuery, ev.DayID).Scan(&planVersionID, &snapshot)
	if errors.Is(err, pgx.ErrNoRows) {
		// Dia inexistente, de outro tenant (RLS filtrou) ou de uma versão que
		// nunca foi publicada — sessão de rascunho não existe.
		res.Status, res.Code = domain.SyncStatusRejected, RejectUnknownDay
		return res, nil
	}
	if err != nil {
		return res, err
	}

	id, err := newID("sessão")
	if err != nil {
		return res, err
	}
	var sessionID string
	err = tx.QueryRow(ctx, `
		INSERT INTO workout_sessions
			(id, tenant_id, student_id, plan_version_id, day_id, snapshot, started_at, client_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (tenant_id, client_id) DO NOTHING
		RETURNING id`,
		id, tenantID, studentID, planVersionID, ev.DayID, snapshot, ev.PerformedAt, ev.ClientID).Scan(&sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		// Reenvio do mesmo evento: devolve o id que já existe para o device
		// poder amarrar os set_logs que ainda estão na fila dele.
		if err := tx.QueryRow(ctx,
			`SELECT id FROM workout_sessions WHERE client_id = $1`, ev.ClientID).Scan(&sessionID); err != nil {
			return res, err
		}
		res.Status, res.SessionID = domain.SyncStatusDuplicate, sessionID
		return res, nil
	}
	if err != nil {
		return res, err
	}
	res.Status, res.SessionID = domain.SyncStatusAccepted, sessionID
	return res, nil
}

// logSet grava uma série executada (ou a correção de uma, ADR-003 §5).
func logSet(ctx context.Context, tx pgx.Tx, tenantID, studentID string, ev domain.SyncEvent) (domain.SyncResult, error) {
	res := domain.SyncResult{ClientID: ev.ClientID}

	var sessionID string
	err := tx.QueryRow(ctx, `
		SELECT id FROM workout_sessions WHERE client_id = $1 AND student_id = $2`,
		ev.SessionClientID, studentID).Scan(&sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		res.Status, res.Code = domain.SyncStatusRejected, RejectUnknownSession
		return res, nil
	}
	if err != nil {
		return res, err
	}

	// A FK de exercise_id roda com os privilégios do dono da tabela e ignora
	// RLS (mesma armadilha do builder no P1.4): sem este SELECT, um id
	// adivinhado de outro tenant entraria no histórico.
	var exists bool
	if err := tx.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM exercises WHERE id = $1)`, ev.ExerciseID).Scan(&exists); err != nil {
		return res, err
	}
	if !exists {
		res.Status, res.Code = domain.SyncStatusRejected, RejectUnknownExercise
		return res, nil
	}

	if ev.Type == domain.SyncEventSetRevision {
		var revised bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM workout_set_logs WHERE client_id = $1)`, ev.Revises).Scan(&revised); err != nil {
			return res, err
		}
		if !revised {
			// Corrigir um log que o servidor não tem deixaria uma revisão
			// órfã escondendo nada. O device reenvia o original primeiro.
			res.Status, res.Code = domain.SyncStatusRejected, RejectUnknownRevisedLog
			return res, nil
		}
	}

	id, err := newID("log de série")
	if err != nil {
		return res, err
	}
	var logID string
	err = tx.QueryRow(ctx, `
		INSERT INTO workout_set_logs
			(id, tenant_id, session_id, exercise_id, set_no, reps_done, load_kg, rpe, performed_at, client_id, revises)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (tenant_id, client_id) DO NOTHING
		RETURNING id`,
		id, tenantID, sessionID, ev.ExerciseID, ev.SetNo, ev.RepsDone, ev.LoadKg, ev.RPE,
		ev.PerformedAt, ev.ClientID, nullString(ev.Revises)).Scan(&logID)
	if errors.Is(err, pgx.ErrNoRows) {
		res.Status, res.SessionID = domain.SyncStatusDuplicate, sessionID
		return res, nil
	}
	if err != nil {
		return res, err
	}
	res.Status, res.SessionID = domain.SyncStatusAccepted, sessionID
	return res, nil
}

// finishSession fecha a sessão e avança a rotação (ADR-004 §3).
//
// A idempotência aqui não vem de UNIQUE, porque terminar é UPDATE e não
// INSERT: o `finished_at IS NULL` no WHERE é que garante que reenviar o lote
// não avance o rodízio duas vezes.
func finishSession(ctx context.Context, tx pgx.Tx, studentID string, ev domain.SyncEvent) (domain.SyncResult, error) {
	res := domain.SyncResult{ClientID: ev.ClientID}

	var sessionID, dayID string
	err := tx.QueryRow(ctx, `
		UPDATE workout_sessions SET finished_at = $3
		WHERE client_id = $1 AND student_id = $2 AND finished_at IS NULL
		RETURNING id, day_id`, ev.SessionClientID, studentID, ev.PerformedAt).Scan(&sessionID, &dayID)
	if errors.Is(err, pgx.ErrNoRows) {
		// Ou a sessão não existe, ou já estava fechada — para o device são
		// desfechos diferentes: um manda reenviar o session_start, o outro é
		// só o ACK que ele não recebeu.
		var finished bool
		err := tx.QueryRow(ctx, `
			SELECT id, finished_at IS NOT NULL FROM workout_sessions
			WHERE client_id = $1 AND student_id = $2`, ev.SessionClientID, studentID).Scan(&sessionID, &finished)
		if errors.Is(err, pgx.ErrNoRows) {
			res.Status, res.Code = domain.SyncStatusRejected, RejectUnknownSession
			return res, nil
		}
		if err != nil {
			return res, err
		}
		res.Status, res.SessionID = domain.SyncStatusDuplicate, sessionID
		return res, nil
	}
	if err != nil {
		return res, err
	}

	// "Sessão com ≥1 set registrado conta como concluída" (ADR-004 §3):
	// abrir o treino e desistir não gasta o dia da rotação.
	var logged int
	if err := tx.QueryRow(ctx,
		`SELECT count(*) FROM workout_set_logs WHERE session_id = $1`, sessionID).Scan(&logged); err != nil {
		return res, err
	}
	if logged > 0 {
		if err := advanceRotation(ctx, tx, studentID, dayID, ev.PerformedAt); err != nil {
			return res, err
		}
	}

	res.Status, res.SessionID = domain.SyncStatusAccepted, sessionID
	return res, nil
}

// advanceRotation move o aluno para o próximo dia do rodízio, circular
// (ADR-004 §3).
//
// O passo é dado sobre a **versão ativa**, não sobre a versão que a sessão
// congelou: quem terminou o A de uma v1 enquanto o coach publicava a v2 vai
// para o B da v2. O casamento é pelo **rótulo** do dia, como no publish
// (P1.4) — se o rótulo sumiu na versão nova, a rotação recomeça no primeiro
// dia.
func advanceRotation(ctx context.Context, tx pgx.Tx, studentID, finishedDayID string, performedAt time.Time) error {
	var activeVersionID string
	err := tx.QueryRow(ctx, `
		SELECT active_version_id FROM student_plan_state
		WHERE student_id = $1 FOR UPDATE`, studentID).Scan(&activeVersionID)
	if errors.Is(err, pgx.ErrNoRows) {
		// Aluno sem plano ativo (o coach arquivou depois que ele começou):
		// não há rotação para avançar, e a sessão continua válida.
		return nil
	}
	if err != nil {
		return err
	}

	var finishedLabel string
	if err := tx.QueryRow(ctx,
		`SELECT label FROM workout_days WHERE id = $1`, finishedDayID).Scan(&finishedLabel); err != nil {
		return err
	}

	// position > posição do dia terminado; se o rótulo não existe na versão
	// ativa, o COALESCE(-1) faz cair no primeiro dia.
	var nextDayID string
	err = tx.QueryRow(ctx, `
		SELECT id FROM workout_days
		WHERE plan_version_id = $1
		  AND position > COALESCE(
		      (SELECT position FROM workout_days WHERE plan_version_id = $1 AND label = $2), -1)
		ORDER BY position LIMIT 1`, activeVersionID, finishedLabel).Scan(&nextDayID)
	if errors.Is(err, pgx.ErrNoRows) {
		// Era o último dia: o rodízio é circular, volta para o primeiro.
		err = tx.QueryRow(ctx, `
			SELECT id FROM workout_days WHERE plan_version_id = $1
			ORDER BY position LIMIT 1`, activeVersionID).Scan(&nextDayID)
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE student_plan_state
		SET next_day_id = $2, last_session_at = $3, updated_at = now()
		WHERE student_id = $1`, studentID, nullString(nextDayID), performedAt)
	return err
}

// PreviousLoads devolve, por exercício pedido, as séries da última sessão em
// que o aluno o executou — a "carga anterior" do ADR-004.
//
// A busca é por `exercise_id` e ignora plano e versão de propósito: o aluno
// que trocou de treino continua vendo com quanto fez o supino da última vez.
func (r *SessionRepo) PreviousLoads(ctx context.Context, tenantID, studentID string, exerciseIDs []string) (map[string]domain.PreviousLoad, error) {
	out := make(map[string]domain.PreviousLoad, len(exerciseIDs))
	if len(exerciseIDs) == 0 {
		return out, nil
	}

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			WITH effective AS (
				SELECT l.exercise_id, l.session_id, l.set_no, l.reps_done, l.load_kg, l.rpe, l.performed_at
				FROM workout_set_logs l
				JOIN workout_sessions s ON s.id = l.session_id
				WHERE s.student_id = $2
				  AND l.exercise_id = ANY($1::uuid[])
				  AND ` + effectiveLogFilter + `
			),
			last_session AS (
				SELECT DISTINCT ON (exercise_id) exercise_id, session_id, performed_at
				FROM effective
				ORDER BY exercise_id, performed_at DESC
			)
			SELECT e.exercise_id, e.session_id, e.set_no, e.reps_done, e.load_kg, e.rpe, e.performed_at
			FROM effective e
			JOIN last_session ls ON ls.exercise_id = e.exercise_id AND ls.session_id = e.session_id
			ORDER BY e.exercise_id, e.set_no`
		rows, err := tx.Query(ctx, q, exerciseIDs, studentID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var (
				exerciseID, sessionID string
				set                   domain.PreviousLoadSet
			)
			if err := rows.Scan(&exerciseID, &sessionID, &set.SetNo, &set.RepsDone,
				&set.LoadKg, &set.RPE, &set.PerformedAt); err != nil {
				return err
			}
			prev, ok := out[exerciseID]
			if !ok {
				prev = domain.PreviousLoad{ExerciseID: exerciseID, SessionID: sessionID}
			}
			// A sessão inteira é a mesma; o mais recente dos performed_at
			// representa quando o exercício foi feito.
			if set.PerformedAt.After(prev.PerformedAt) {
				prev.PerformedAt = set.PerformedAt
			}
			prev.Sets = append(prev.Sets, set)
			out[exerciseID] = prev
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: buscar carga anterior: %w", err)
	}
	return out, nil
}

// RecentSessions resume as últimas sessões do aluno para a tela Hoje.
func (r *SessionRepo) RecentSessions(ctx context.Context, tenantID, studentID string, limit int) ([]domain.SessionSummary, error) {
	if limit <= 0 {
		limit = maxRecentSessions
	}
	var out []domain.SessionSummary

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT s.id,
			       COALESCE(s.snapshot -> 'day' ->> 'label', ''),
			       s.started_at, s.finished_at,
			       count(l.id),
			       COALESCE(sum(l.load_kg * l.reps_done), 0)
			FROM workout_sessions s
			LEFT JOIN workout_set_logs l
			       ON l.session_id = s.id AND ` + effectiveLogFilter + `
			WHERE s.student_id = $1
			GROUP BY s.id
			ORDER BY s.started_at DESC
			LIMIT $2`
		rows, err := tx.Query(ctx, q, studentID, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.SessionSummary
			if err := rows.Scan(&s.ID, &s.DayLabel, &s.StartedAt, &s.FinishedAt,
				&s.TotalSets, &s.TotalVolumeKg); err != nil {
				return err
			}
			out = append(out, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar sessões recentes: %w", err)
	}
	return out, nil
}

// SessionsInRange devolve as sessões do aluno com `started_at` dentro de
// [from, to) — a leitura da agenda semanal (P4.1).
//
// O filtro é por `started_at` (o `performed_at` que o device mandou ao abrir
// a sessão, ver `startSession`), não por `received_at`: ADR-003 é explícito —
// "relatórios usam performed_at com sanidade validada" (a sanidade é o
// clock-skew do sync, P1.5). A agenda precisa mostrar o treino no dia em que
// ele **aconteceu**, não no dia em que o device conseguiu sincronizar; um
// aluno que treina offline no sábado e só reconecta na segunda não pode ver
// o treino cair na segunda-feira. `idx_workout_sessions_student
// (tenant_id, student_id, started_at DESC)`, já criado na P1.1, cobre esta
// consulta — nenhuma migration nova foi necessária.
func (r *SessionRepo) SessionsInRange(ctx context.Context, tenantID, studentID string, from, to time.Time) ([]domain.SessionSummary, error) {
	var out []domain.SessionSummary

	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		const q = `
			SELECT s.id,
			       COALESCE(s.snapshot -> 'day' ->> 'label', ''),
			       s.started_at, s.finished_at,
			       count(l.id),
			       COALESCE(sum(l.load_kg * l.reps_done), 0)
			FROM workout_sessions s
			LEFT JOIN workout_set_logs l
			       ON l.session_id = s.id AND ` + effectiveLogFilter + `
			WHERE s.student_id = $1
			  AND s.started_at >= $2 AND s.started_at < $3
			GROUP BY s.id
			ORDER BY s.started_at ASC`
		rows, err := tx.Query(ctx, q, studentID, from, to)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.SessionSummary
			if err := rows.Scan(&s.ID, &s.DayLabel, &s.StartedAt, &s.FinishedAt,
				&s.TotalSets, &s.TotalVolumeKg); err != nil {
				return err
			}
			out = append(out, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("repo: listar sessões por período: %w", err)
	}
	return out, nil
}

// SessionSnapshot devolve o snapshot congelado de uma sessão do aluno. É o que
// permite reabrir uma execução sem depender do template vivo (ADR-004 §2).
func (r *SessionRepo) SessionSnapshot(ctx context.Context, tenantID, studentID, sessionID string) (json.RawMessage, error) {
	var snapshot json.RawMessage
	err := WithTenant(ctx, r.pool, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT snapshot FROM workout_sessions WHERE id = $1 AND student_id = $2`,
			sessionID, studentID).Scan(&snapshot)
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("repo: ler snapshot da sessão: %w", err)
	}
	return snapshot, nil
}

// daySnapshotQuery monta a cópia desnormalizada do dia (ADR-004 §2) em uma
// consulta só. O nome que entra no snapshot é a coluna canônica
// `exercises.name`: o snapshot é registro histórico, e a tradução para a
// língua do aluno é resolvida na leitura (ADR-011 §2) — congelar o texto
// traduzido deixaria o histórico preso ao idioma do dia em que foi feito.
//
// Só dia de versão **publicada** vira sessão: rascunho não é treino.
const daySnapshotQuery = `
	SELECT d.plan_version_id,
	       jsonb_build_object(
	           'plan_version_id', d.plan_version_id,
	           'day', jsonb_build_object(
	               'id', d.id, 'label', d.label, 'position', d.position, 'title', d.title
	           ),
	           'blocks', COALESCE((
	               SELECT jsonb_agg(jsonb_build_object(
	                   'id', b.id,
	                   'position', b.position,
	                   'block_type', b.block_type,
	                   'rest_seconds', b.rest_seconds,
	                   'exercises', COALESCE((
	                       SELECT jsonb_agg(jsonb_build_object(
	                           'id', be.id,
	                           'exercise_id', be.exercise_id,
	                           'position', be.position,
	                           'notes', be.notes,
	                           'name', e.name,
	                           'media_url', e.media_url,
	                           'media_type', e.media_type,
	                           'sets', COALESCE((
	                               SELECT jsonb_agg(jsonb_build_object(
	                                   'set_no', ps.set_no,
	                                   'reps_min', ps.reps_min,
	                                   'reps_max', ps.reps_max,
	                                   'target_load_kg', ps.target_load_kg,
	                                   'target_unit', ps.target_unit,
	                                   'target_value', ps.target_value,
	                                   'rest_seconds', ps.rest_seconds,
	                                   'tempo', ps.tempo
	                               ) ORDER BY ps.set_no)
	                               FROM prescribed_sets ps WHERE ps.block_exercise_id = be.id
	                           ), '[]'::jsonb)
	                       ) ORDER BY be.position)
	                       FROM block_exercises be
	                       JOIN exercises e ON e.id = be.exercise_id
	                       WHERE be.block_id = b.id
	                   ), '[]'::jsonb)
	               ) ORDER BY b.position)
	               FROM workout_blocks b WHERE b.day_id = d.id
	           ), '[]'::jsonb)
	       )
	FROM workout_days d
	JOIN workout_plan_versions v ON v.id = d.plan_version_id
	WHERE d.id = $1 AND v.published_at IS NOT NULL`

// ServerTime devolve o relógio do **banco**, não o do processo. É a marca
// d'água do pull incremental (P1.5): comparar `updated_at` (carimbado por
// now() do Postgres) com o relógio da API só funciona enquanto os dois
// relógios coincidem — e "coincidem quase sempre" é como se perde uma
// atualização em produção.
func (r *SessionRepo) ServerTime(ctx context.Context) (time.Time, error) {
	var now time.Time
	if err := r.pool.QueryRow(ctx, "SELECT now()").Scan(&now); err != nil {
		return time.Time{}, fmt.Errorf("repo: ler relógio do banco: %w", err)
	}
	return now.UTC(), nil
}
