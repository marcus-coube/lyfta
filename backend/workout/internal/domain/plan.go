package domain

import "time"

// PlanStatus é o ciclo de vida do template do aluno.
type PlanStatus string

const (
	PlanStatusDraft     PlanStatus = "draft"
	PlanStatusPublished PlanStatus = "published"
	PlanStatusArchived  PlanStatus = "archived"
)

// BlockType representa o agrupamento de execução (ADR-004 §1): um exercício
// "normal" é um bloco straight com um exercício só.
type BlockType string

const (
	BlockTypeStraight  BlockType = "straight"
	BlockTypeSuperset  BlockType = "superset"
	BlockTypeDropset   BlockType = "dropset"
	BlockTypeRestPause BlockType = "rest_pause"
	BlockTypeCircuit   BlockType = "circuit"
)

// TargetUnit é a unidade do alvo de carga do set (ADR-012 §4).
type TargetUnit string

const (
	TargetUnitKg         TargetUnit = "kg"
	TargetUnitPercent1RM TargetUnit = "percent_1rm"
	TargetUnitRPE        TargetUnit = "rpe"
	TargetUnitRIR        TargetUnit = "rir"
)

// Plan é o template do aluno — mutável, mas só através de versões novas.
// StudentID e CoachID são users.id do identity: referência por UUID, sem FK,
// porque cada serviço tem seu banco (ADR-013 §2).
type Plan struct {
	ID        string
	TenantID  string
	StudentID string
	CoachID   string
	Title     string
	Status    PlanStatus
	CreatedAt time.Time
	UpdatedAt time.Time
}

// PlanVersion é uma versão do plano. Depois de publicada (PublishedAt não
// nulo) ela e toda a sua árvore ficam imutáveis — garantido por trigger no
// banco, não só pela aplicação (ADR-004 §1).
type PlanVersion struct {
	ID          string
	TenantID    string
	PlanID      string
	VersionNo   int
	PublishedAt *time.Time
	CreatedAt   time.Time
}

// Day é um dia da rotação (A, B, C…) dentro de uma versão (ADR-004 §3).
type Day struct {
	ID            string
	TenantID      string
	PlanVersionID string
	Label         string
	Position      int
	Title         string
	Blocks        []Block
}

// Block agrupa exercícios executados juntos (superset, circuito, drop set).
type Block struct {
	ID          string
	TenantID    string
	DayID       string
	Position    int
	BlockType   BlockType
	RestSeconds int
	Exercises   []BlockExercise
}

// BlockExercise é a posição de um exercício dentro do bloco.
type BlockExercise struct {
	ID         string
	TenantID   string
	BlockID    string
	ExerciseID string
	Position   int
	Notes      string
	Sets       []PrescribedSet
}

// PrescribedSet é a prescrição estruturada de uma série (ADR-012 §4): reps,
// carga alvo, descanso e cadência — nunca texto livre, porque o gráfico de
// carga do MVP 1.0 depende desses campos serem consultáveis.
//
// Ponteiros distinguem "não prescrito" de zero: 0 kg é uma carga alvo válida
// (peso corporal), enquanto NULL significa que o coach não prescreveu carga.
type PrescribedSet struct {
	ID              string
	TenantID        string
	BlockExerciseID string
	SetNo           int
	RepsMin         *int
	RepsMax         *int
	TargetLoadKg    *float64
	TargetUnit      *TargetUnit
	TargetValue     *float64
	RestSeconds     *int
	Tempo           string
}
