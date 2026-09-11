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

// Locale é o idioma de renderização do push (ADR-011 §3: o servidor
// renderiza no locale do destinatário) — os três do lançamento (ADR-011 §1).
const (
	LocalePTBR = "pt-BR"
	LocalePTPT = "pt-PT"
	LocaleEN   = "en"
)

// IsValidLocale confere se v é um dos três locales do lançamento.
func IsValidLocale(v string) bool {
	return v == LocalePTBR || v == LocalePTPT || v == LocaleEN
}

// DevicePlatform é a plataforma do device que registrou o token de push
// (P3.4) — mesmas três da migration 0004_device_tokens.
type DevicePlatform string

const (
	PlatformAndroid DevicePlatform = "android"
	PlatformIOS     DevicePlatform = "ios"
	PlatformWeb     DevicePlatform = "web"
)

// IsValidPlatform confere se v é uma DevicePlatform conhecida.
func IsValidPlatform(v DevicePlatform) bool {
	return v == PlatformAndroid || v == PlatformIOS || v == PlatformWeb
}

// DeviceToken é o token de push de um device (P3.4) — upsert por
// tenant+user+platform (migration 0004). Locale é gravado no momento do
// registro (POST /v1/devices): é a única fonte do idioma do destinatário
// disponível fora de uma requisição HTTP dele (o job diário roda numa
// goroutine, sem claim — ver Notas de execução da P3.4).
type DeviceToken struct {
	ID        string
	TenantID  string
	UserID    string
	Platform  DevicePlatform
	Token     string
	Locale    string
	UpdatedAt time.Time
}
