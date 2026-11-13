package domain

import (
	"math"
	"time"
)

// Teto de duração confiável: acima disso (ou negativa) o relógio do device
// não é de confiança (ADR-003) e a duração some em vez de mentir.
const maxTrustedSessionDuration = 12 * time.Hour

// SessionMetrics são os números do resumo de uma sessão. **Definição única**,
// espelho de `app/lib/features/workout/domain/session_metrics.dart` (P10.2):
// quem muda uma muda a outra.
//
//   - Sets = logs efetivos (corrigir uma série não conta duas vezes);
//   - Reps = Σ reps_done;
//   - VolumeKg = Σ carga × reps;
//   - DurationSeconds = finished_at − started_at, nulo sem fim, negativa ou
//     acima de 12 h.
type SessionMetrics struct {
	Sets            int
	Reps            int
	VolumeKg        float64
	DurationSeconds *int
}

// MeasureSession calcula as métricas. logs deve vir **já efetivo** (sem os
// logs apontados por `revises`; ver `effectiveLogFilter` no repo).
func MeasureSession(logs []SetLog, startedAt time.Time, finishedAt *time.Time) SessionMetrics {
	m := SessionMetrics{Sets: len(logs)}
	var volume float64
	for _, l := range logs {
		if l.RepsDone != nil {
			m.Reps += *l.RepsDone
			if l.LoadKg != nil {
				volume += *l.LoadKg * float64(*l.RepsDone)
			}
		}
	}
	m.VolumeKg = math.Round(volume*100) / 100
	if finishedAt != nil {
		d := finishedAt.Sub(startedAt)
		if d >= 0 && d <= maxTrustedSessionDuration {
			secs := int(d.Seconds())
			m.DurationSeconds = &secs
		}
	}
	return m
}
