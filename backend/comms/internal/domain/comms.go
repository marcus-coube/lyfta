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
