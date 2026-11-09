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
	// Timezone é o nome IANA do fuso do tenant (ADR-007 §3): "hoje", "mês
	// corrente" e vencimento se calculam nele (P5.1).
	Timezone string
	// CoachBillingAccess define o que o coach vê do financeiro (ADR-017 §3).
	CoachBillingAccess string
}

// DefaultTimezone é o fuso de todo tenant até o owner mudar (ADR-007 §3).
const DefaultTimezone = "America/Sao_Paulo"

// Valores de Tenant.CoachBillingAccess (ADR-017 §3).
const (
	CoachBillingStatusOnly  = "status_only"
	CoachBillingOwnStudents = "own_students"
)

// IsKnownCoachBillingAccess diz se o valor existe.
func IsKnownCoachBillingAccess(v string) bool {
	return v == CoachBillingStatusOnly || v == CoachBillingOwnStudents
}

// UserStatus é o ciclo de vida de um usuário dentro do tenant.
type UserStatus string

const (
	UserStatusInvited  UserStatus = "invited"
	UserStatusActive   UserStatus = "active"
	UserStatusDisabled UserStatus = "disabled"
	// UserStatusInactive é o aluno desativado pelo professor/owner (P5.2): não
	// loga, some da lista padrão e mantém todos os dados.
	UserStatusInactive UserStatus = "inactive"
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
	// Phone e BirthDate (AAAA-MM-DD) são opcionais (P5.2).
	Phone     *string
	BirthDate *string
	// CoachID/CoachName só vêm preenchidos na listagem, para aluno com vínculo
	// (ADR-016).
	CoachID   *string
	CoachName *string
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

// Invitation representa o convite de um coach/owner para um e-mail entrar no
// tenant (P0.4). Token opaco, hash em banco, uso único (accepted_at).
type Invitation struct {
	ID         string
	TenantID   string
	Email      string
	Role       Role
	TokenHash  string
	InvitedBy  string
	ExpiresAt  time.Time
	AcceptedAt *time.Time
	CreatedAt  time.Time
}

// PasswordReset representa um pedido de recuperação de senha (P0.4). Token
// opaco, hash em banco, uso único (used_at).
type PasswordReset struct {
	ID        string
	UserID    string
	TenantID  string
	TokenHash string
	ExpiresAt time.Time
	UsedAt    *time.Time
	CreatedAt time.Time
}

// UserStatusDeleting e UserStatusDeleted marcam as duas fases da exclusão de
// conta (ADR-008 §2, P4.5): `deleting` bloqueia o login enquanto os outros
// serviços apagam o que é do usuário; `deleted` é o usuário já anonimizado.
const (
	UserStatusDeleting UserStatus = "deleting"
	UserStatusDeleted  UserStatus = "deleted"
)

// Finalidades de consentimento (ADR-008 §1). `terms` é o aceite dos termos e
// da política de privacidade — vale para todo papel; `health_data` e
// `progress_photos` são as finalidades de saúde do aluno. GPS entra com o
// running (4.0).
const (
	PurposeTerms          = "terms"
	PurposeHealthData     = "health_data"
	PurposeProgressPhotos = "progress_photos"
)

// IsKnownPurpose diz se a finalidade existe.
func IsKnownPurpose(p string) bool {
	switch p {
	case PurposeTerms, PurposeHealthData, PurposeProgressPhotos:
		return true
	}
	return false
}

// RequiredPurposes são as finalidades sem as quais o usuário não entra no
// app: os termos para todos e, para o aluno, os dados de saúde.
func RequiredPurposes(roles []Role) []string {
	required := []string{PurposeTerms}
	for _, r := range roles {
		if r == RoleStudent {
			required = append(required, PurposeHealthData)
			break
		}
	}
	return required
}

// Consent é uma linha do registro append-only de consentimentos: revogar grava
// RevokedAt, nunca apaga (ADR-008 §1).
type Consent struct {
	ID           string
	TenantID     string
	UserID       string
	Purpose      string
	TermsVersion string
	GrantedAt    time.Time
	RevokedAt    *time.Time
}
