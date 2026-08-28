package domain

import "time"

// SyncEventType são os quatro fatos que o device empilha na fila local
// enquanto executa o treino (ADR-003 §4). O lote é uma fila drenada em ordem,
// não um conjunto: `set_log` referencia a sessão pelo `client_id` que o
// device gerou, porque offline ele não conhece nenhum id do servidor.
type SyncEventType string

const (
	SyncEventSessionStart  SyncEventType = "session_start"
	SyncEventSetLog        SyncEventType = "set_log"
	SyncEventSetRevision   SyncEventType = "set_revision"
	SyncEventSessionFinish SyncEventType = "session_finish"
)

// IsValidSyncEventType diz se o tipo pertence ao contrato do ADR-003 §4.
func IsValidSyncEventType(v SyncEventType) bool {
	switch v {
	case SyncEventSessionStart, SyncEventSetLog, SyncEventSetRevision, SyncEventSessionFinish:
		return true
	default:
		return false
	}
}

// SyncEvent é um evento da fila offline já validado pelo handler. Os campos
// de payload são um union achatado: cada tipo usa os seus e ignora o resto —
// mais simples que quatro structs para um contrato de quatro casos.
//
// PerformedAt vem do device (quando o aluno fez); o servidor carimba quando
// recebeu (ADR-003: relógio do device não é confiável).
type SyncEvent struct {
	ClientID    string
	Type        SyncEventType
	PerformedAt time.Time

	// session_start
	DayID string

	// set_log, set_revision, session_finish
	SessionClientID string

	// set_log, set_revision
	ExerciseID string
	SetNo      int
	RepsDone   *int
	LoadKg     *float64
	RPE        *float64

	// set_revision: client_id do log corrigido (ADR-003 §5).
	Revises string
}

// SyncStatus é o desfecho de um evento do lote. `duplicate` não é erro: é a
// resposta esperada quando o device reenvia a fila inteira porque não viu o
// ACK anterior — é o que torna o push idempotente (ADR-003 §4).
type SyncStatus string

const (
	SyncStatusAccepted  SyncStatus = "accepted"
	SyncStatusDuplicate SyncStatus = "duplicate"
	SyncStatusRejected  SyncStatus = "rejected"
)

// SyncResult é o desfecho de um evento, devolvido na mesma ordem do lote.
// Code só existe em rejeição, e é código estável para o cliente traduzir
// (ADR-011 §3).
type SyncResult struct {
	ClientID  string
	Status    SyncStatus
	Code      string
	SessionID string
}

// PreviousLoadSet é uma série da última execução daquele exercício.
type PreviousLoadSet struct {
	SetNo       int
	RepsDone    *int
	LoadKg      *float64
	RPE         *float64
	PerformedAt time.Time
}

// PreviousLoad é a "carga anterior" do ADR-004: as séries da última sessão em
// que o aluno executou aquele exercício, independente de plano ou versão —
// `exercise_id` é o eixo estável de progresso. Logs corrigidos por um
// `set_revision` não entram.
type PreviousLoad struct {
	ExerciseID  string
	SessionID   string
	PerformedAt time.Time
	Sets        []PreviousLoadSet
}

// SessionSummary é a linha do histórico recente mostrada na tela Hoje.
// TotalVolumeKg é Σ(carga × reps) das séries efetivas — a métrica que o
// resumo de fim de sessão também usa.
type SessionSummary struct {
	ID            string
	DayLabel      string
	StartedAt     time.Time
	FinishedAt    *time.Time
	TotalSets     int
	TotalVolumeKg float64
}
