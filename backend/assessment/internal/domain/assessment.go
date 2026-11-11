// Package domain contém os tipos e regras de negócio do serviço assessment:
// medidas corporais, bioimpedância e fotos de evolução (ADR-012 §2, entrada
// manual — sem integração com balança nesta fase).
package domain

import "time"

// BodyMeasurement é uma medida corporal digitada (P2.2). Só measured_at é
// obrigatório: os demais campos são o que o coach ou o aluno mediu naquele
// dia, e ficam nulos quando não medidos.
type BodyMeasurement struct {
	ID         string
	TenantID   string
	StudentID  string
	MeasuredAt time.Time
	WeightKg   *float64
	HeightCm   *float64
	NeckCm     *float64
	ShoulderCm *float64
	ChestCm    *float64
	WaistCm    *float64
	AbdomenCm  *float64
	HipCm      *float64
	ArmLCm     *float64
	ArmRCm     *float64
	ThighLCm   *float64
	ThighRCm   *float64
	CalfLCm    *float64
	CalfRCm    *float64
	Notes      string
	CreatedBy  string // users.id de quem lançou (aluno ou coach)
	CreatedAt  time.Time
}

// BioimpedanceRecord é uma leitura de bioimpedância digitada (ADR-012 §2):
// integração com balança fica para 3.0+, aqui é sempre o coach ou o aluno
// transcrevendo o que o aparelho mostrou.
type BioimpedanceRecord struct {
	ID           string
	TenantID     string
	StudentID    string
	MeasuredAt   time.Time
	BodyFatPct   *float64
	MuscleMassKg *float64
	VisceralFat  *float64
	BodyWaterPct *float64
	BoneMassKg   *float64
	BMRKcal      *int
	Notes        string
	CreatedBy    string
	CreatedAt    time.Time
}

// Pose é o ângulo da foto de evolução.
type Pose string

const (
	PoseFront Pose = "front"
	PoseSide  Pose = "side"
	PoseBack  Pose = "back"
)

// IsValidPose confere se p é uma das três poses aceitas (mesmo CHECK da
// migration 0003).
func IsValidPose(p Pose) bool {
	switch p {
	case PoseFront, PoseSide, PoseBack:
		return true
	}
	return false
}

// ProgressPhoto é uma foto de evolução. MediaKey é sempre preenchida — ao
// contrário da mídia de exercício, uma foto sem mídia não é um registro
// válido.
type ProgressPhoto struct {
	ID        string
	TenantID  string
	StudentID string
	TakenAt   time.Time
	Pose      Pose
	MediaKey  string
	Notes     string
	CreatedBy string
	CreatedAt time.Time
}

// StudentSummary é o resumo que o coach vê na ficha do aluno (P2.3): última
// medida e última bioimpedância, com a leitura anterior ao lado para calcular
// deltas, mais a contagem de fotos.
type StudentSummary struct {
	LatestMeasurement    *BodyMeasurement
	PreviousMeasurement  *BodyMeasurement
	LatestBioimpedance   *BioimpedanceRecord
	PreviousBioimpedance *BioimpedanceRecord
	PhotoCount           int
}
