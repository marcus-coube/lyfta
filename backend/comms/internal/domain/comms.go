// Package domain contém os tipos e regras de negócio do serviço comms —
// conversa, mensagem (P3.2), check-in de treino (P3.3) chegam aqui conforme
// as tarefas avançam.
package domain

import "time"

// MessageType é o tipo de conteúdo de uma mensagem — texto ou imagem
// (ADR-012 §2 restringe o MVP a esses dois; mídia rica fica pro 3.0).
type MessageType string

const (
	MessageTypeText  MessageType = "text"
	MessageTypeImage MessageType = "image"
)

// IsValidMessageType confere se v é um MessageType conhecido.
func IsValidMessageType(v MessageType) bool {
	return v == MessageTypeText || v == MessageTypeImage
}

// Conversation é o par aluno-coach (única por tenant, migration 0001).
type Conversation struct {
	ID            string
	TenantID      string
	StudentID     string
	CoachID       string
	CreatedAt     time.Time
	LastMessageAt *time.Time
}

// Message é um item append-only do histórico de uma conversa.
type Message struct {
	ID             string
	TenantID       string
	ConversationID string
	SenderID       string
	Type           MessageType
	Body           string
	MediaKey       string
	CreatedAt      time.Time
	ReadAt         *time.Time
}

// ConversationSummary é a linha de GET /v1/conversations — a conversa mais a
// prévia da última mensagem e o contador de não lidas do ponto de vista de
// quem pediu a lista.
type ConversationSummary struct {
	Conversation
	LastMessage *Message
	UnreadCount int
}

// PainLevel é a dor relatada no check-in de treino (P3.3) — `strong` é o
// gatilho do push imediato pro coach (P3.4).
type PainLevel string

const (
	PainNone   PainLevel = "none"
	PainMild   PainLevel = "mild"
	PainStrong PainLevel = "strong"
)

// IsValidPainLevel confere se v é um PainLevel conhecido.
func IsValidPainLevel(v PainLevel) bool {
	return v == PainNone || v == PainMild || v == PainStrong
}

// IsValidCheckinScore confere se v está no intervalo 1..5 usado tanto por
// `rating` quanto por `difficulty` (migration 0003).
func IsValidCheckinScore(v int) bool {
	return v >= 1 && v <= 5
}

// WorkoutCheckin é a avaliação estruturada que o aluno registra ao concluir
// o treino (ADR-012 §2) — idempotente por (tenant_id, session_client_id), o
// mesmo client_id da sessão no serviço workout (ADR-003 §2, sem FK entre
// bancos, ADR-013 §2).
type WorkoutCheckin struct {
	ID              string
	TenantID        string
	StudentID       string
	SessionClientID string
	Rating          int
	Difficulty      int
	Pain            PainLevel
	PainNotes       string
	Comment         string
	CreatedAt       time.Time
	ReviewedBy      string
	ReviewedAt      *time.Time
}
