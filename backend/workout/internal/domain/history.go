package domain

import "time"

// HistoryPoint é um ponto do gráfico de progressão: o que o aluno fez de um
// exercício **numa sessão**. O eixo é o `exercise_id`, não o plano — trocar de
// plano ou republicar a versão não corta a série histórica (ADR-004 §2).
//
// MaxLoadKg é a maior carga das séries efetivas; TotalVolumeKg é Σ(reps ×
// carga). Exercício sem carga (corpo livre, tempo) tem MaxLoadKg nulo e volume
// zero — a tela mostra reps, não uma carga inventada.
type HistoryPoint struct {
	SessionID     string
	PerformedAt   time.Time
	Sets          int
	MaxLoadKg     *float64
	TotalVolumeKg float64
	TopSet        HistoryTopSet
}

// HistoryTopSet é a melhor série da sessão: maior carga, desempatando por mais
// repetições e depois pela série mais cedo. É a linha que o aluno lembra
// ("bati 45 kg por 8"), e por isso vai separada dos agregados.
type HistoryTopSet struct {
	SetNo    int
	RepsDone *int
	LoadKg   *float64
}

// LoggedExercise é uma entrada do índice da tela Evolução: exercício que o
// aluno já executou pelo menos uma vez, com o tamanho e a ponta da série.
type LoggedExercise struct {
	ExerciseID      string
	Sessions        int
	LastPerformedAt time.Time
}
