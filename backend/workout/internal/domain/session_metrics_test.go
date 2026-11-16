package domain_test

import (
	"testing"
	"time"

	"github.com/marcus-coube/duo/workout/internal/domain"
)

func TestMeasureSessionDuration(t *testing.T) {
	start := time.Now()
	at := func(d time.Duration) *time.Time { v := start.Add(d); return &v }
	cases := []struct {
		name string
		end  *time.Time
		want *int
	}{
		{"sem fim", nil, nil},
		{"normal", at(45 * time.Minute), ptr(2700)},
		{"negativa", at(-time.Minute), nil},
		{"acima de 12h", at(12*time.Hour + time.Second), nil},
		{"exatamente 12h", at(12 * time.Hour), ptr(43200)},
	}
	for _, c := range cases {
		got := domain.MeasureSession(nil, start, c.end).DurationSeconds
		if (got == nil) != (c.want == nil) || (got != nil && *got != *c.want) {
			t.Errorf("%s: esperava %v, veio %v", c.name, c.want, got)
		}
	}
}

func TestMeasureSessionTotals(t *testing.T) {
	reps, load := 10, 40.0
	logs := []domain.SetLog{
		{RepsDone: &reps, LoadKg: &load},
		{RepsDone: &reps}, // sem carga: conta reps, não volume
		{LoadKg: &load},   // sem reps: conta série, nada mais
	}
	m := domain.MeasureSession(logs, time.Now(), nil)
	if m.Sets != 3 || m.Reps != 20 || m.VolumeKg != 400 {
		t.Fatalf("totais: %+v", m)
	}
}

func ptr(i int) *int { return &i }
