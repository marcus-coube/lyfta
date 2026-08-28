package domain

import (
	"encoding/json"
	"time"
)

// Session é a execução de um dia de treino (ADR-004 §2). Snapshot é a cópia
// desnormalizada da versão do plano congelada no início — o histórico do
// aluno nunca depende do template vivo.
//
// ClientID é o UUID gerado no device (ADR-003 §2), chave de idempotência do
// push offline. ReceivedAt é o carimbo do servidor: o relógio do device não é
// confiável.
type Session struct {
	ID            string
	TenantID      string
	StudentID     string
	PlanVersionID string
	DayID         string
	Snapshot      json.RawMessage
	StartedAt     time.Time
	FinishedAt    *time.Time
	ClientID      string
	ReceivedAt    time.Time
}

// SetLog é o fato imutável de uma série executada (ADR-003 §2): criado só
// pelo próprio aluno, nunca editado. Corrigir um registro errado gera outro
// log com Revises apontando para o ClientID do log revisado (ADR-003 §5).
//
// PerformedAt vem do device; LoggedAt é o carimbo do servidor.
type SetLog struct {
	ID          string
	TenantID    string
	SessionID   string
	ExerciseID  string
	SetNo       int
	RepsDone    *int
	LoadKg      *float64
	RPE         *float64
	PerformedAt time.Time
	LoggedAt    time.Time
	ClientID    string
	Revises     *string
}

// StudentPlanState é a rotação A→B→C do aluno (ADR-004 §3): plano ativo,
// próximo dia e última execução, com override manual permitido.
type StudentPlanState struct {
	TenantID        string
	StudentID       string
	PlanID          string
	ActiveVersionID string
	NextDayID       *string
	LastSessionAt   *time.Time
	UpdatedAt       time.Time
}
