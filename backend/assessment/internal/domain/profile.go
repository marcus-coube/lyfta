package domain

import "time"

// Códigos estáveis da anamnese (P5.3). O rótulo traduzido é do cliente
// (ADR-011); a lista espelha os CHECKs da migration 0005.
var (
	Goals       = []string{"hypertrophy", "weight_loss", "strength", "conditioning", "health", "rehab", "other"}
	Experiences = []string{"beginner", "intermediate", "advanced"}
	BodyRegions = []string{"neck", "shoulder", "elbow", "wrist_hand", "upper_back", "lower_back", "chest", "hip", "knee", "ankle_foot", "other"}
)

// StudentProfile é a anamnese de um aluno. Campos nulos = não informado.
type StudentProfile struct {
	TenantID           string
	StudentID          string
	Goal               *string
	GoalNotes          string
	TrainingExperience *string
	WeeklyTarget       *int
	MedicalNotes       string
	CoachNotes         string
	UpdatedAt          time.Time
	UpdatedBy          string
}

// StudentInjury é uma lesão ou restrição. Ativa enquanto ResolvedAt é nulo.
type StudentInjury struct {
	ID          string
	TenantID    string
	StudentID   string
	BodyRegion  string
	Description string
	Since       *time.Time
	ResolvedAt  *time.Time
	CreatedBy   string
	CreatedAt   time.Time
}

// Contains diz se code está na lista de códigos.
func Contains(list []string, code string) bool {
	for _, c := range list {
		if c == code {
			return true
		}
	}
	return false
}
