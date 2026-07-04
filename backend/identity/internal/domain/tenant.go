// Package domain contém os tipos e regras de negócio do serviço identity.
package domain

import "time"

// Tenant representa uma academia/estúdio/personal — a unidade de isolamento
// multi-tenant (ADR-001).
type Tenant struct {
	ID        string
	Name      string
	Slug      string
	Locale    string
	CreatedAt time.Time
}

// UserStatus é o ciclo de vida de um usuário dentro do tenant.
type UserStatus string

const (
	UserStatusInvited  UserStatus = "invited"
	UserStatusActive   UserStatus = "active"
	UserStatusDisabled UserStatus = "disabled"
)

// Role é o papel do usuário dentro do tenant (ADR-002: atributo do usuário,
// não membership — um usuário pode acumular papéis).
type Role string

const (
	RoleOwner   Role = "owner"
	RoleCoach   Role = "coach"
	RoleStudent Role = "student"
)

// User representa uma conta dentro de um tenant (ADR-002: e-mail único por
// tenant, não globalmente).
type User struct {
	ID           string
	TenantID     string
	Email        string
	PasswordHash string
	Name         string
	Locale       string
	Status       UserStatus
	Roles        []Role
	CreatedAt    time.Time
}
