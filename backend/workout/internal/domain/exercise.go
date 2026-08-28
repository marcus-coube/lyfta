// Package domain tem os tipos e regras de negócio do serviço workout
// (ADR-004: template versionado vs execução imutável).
package domain

import "time"

// MediaType é o tipo de mídia demonstrativa do exercício (ADR-010).
type MediaType string

const (
	MediaTypeGIF   MediaType = "gif"
	MediaTypeVideo MediaType = "video"
)

// Level é o nível sugerido do exercício (taxonomia mínima, ADR-010 §4).
type Level string

const (
	LevelBeginner     Level = "beginner"
	LevelIntermediate Level = "intermediate"
	LevelAdvanced     Level = "advanced"
)

// ExerciseStatus controla a visibilidade do exercício na biblioteca.
type ExerciseStatus string

const (
	ExerciseStatusActive   ExerciseStatus = "active"
	ExerciseStatusArchived ExerciseStatus = "archived"
)

// Exercise é um item da biblioteca. TenantID vazio significa exercício
// **global** da Lyfta (ADR-010 §3): legível por qualquer tenant, editável por
// nenhum — os globais entram por seed administrativo, não pela API.
type Exercise struct {
	ID            string
	TenantID      string
	Name          string
	PrimaryMuscle string
	Equipment     string
	Level         Level
	MediaURL      string
	MediaType     MediaType
	CreatedBy     string
	Status        ExerciseStatus
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

// Locale são os idiomas suportados no conteúdo dinâmico (ADR-011 §2).
type Locale string

const (
	LocalePtBR Locale = "pt-BR"
	LocalePtPT Locale = "pt-PT"
	LocaleEN   Locale = "en"
)

// ExerciseTranslation é o nome/instrução do exercício num idioma. O fallback
// pt-PT → pt-BR → en é resolvido na leitura (P1.3), não aqui.
type ExerciseTranslation struct {
	ExerciseID   string
	TenantID     string
	Locale       Locale
	Name         string
	Instructions string
}
