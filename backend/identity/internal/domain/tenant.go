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

// TenantMatch identifica um tenant onde um e-mail tem conta ativa — usado na
// resolução de login entre tenants (ADR-002 §2b/2c).
type TenantMatch struct {
	UserID     string
	TenantID   string
	TenantName string
}

// RefreshToken representa um refresh token emitido (hash em banco, nunca o
// valor em claro — P0.3).
type RefreshToken struct {
	ID        string
	UserID    string
	TenantID  string
	TokenHash string
	ExpiresAt time.Time
	RevokedAt *time.Time
	CreatedAt time.Time
}
