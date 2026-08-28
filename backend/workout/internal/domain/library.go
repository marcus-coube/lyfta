package domain

import "strings"

// Taxonomia mínima da biblioteca (ADR-010 §4). São **códigos estáveis**, não
// rótulos: quem traduz "chest" para "peitoral"/"peito"/"chest" é o app
// (ADR-011 §5 — nenhuma string de UI nasce no backend). Padrão de movimento e
// o mapa músculo→esforço do ADR-010 ficam para o muscle map (fora do MVP 1.0).
var (
	// Muscles são os grupos musculares aceitos em Exercise.PrimaryMuscle.
	Muscles = []string{
		"chest", "back", "lats", "traps", "lower_back", "shoulders",
		"biceps", "triceps", "forearms", "abs", "obliques",
		"quadriceps", "hamstrings", "glutes", "calves", "adductors",
		"abductors", "full_body",
	}

	// EquipmentTypes são os equipamentos aceitos em Exercise.Equipment.
	EquipmentTypes = []string{
		"barbell", "dumbbell", "machine", "cable", "smith", "bodyweight",
		"kettlebell", "band", "bench", "other",
	}
)

// IsValidMuscle diz se o código de grupo muscular pertence à taxonomia.
func IsValidMuscle(v string) bool { return contains(Muscles, v) }

// IsValidEquipment diz se o código de equipamento pertence à taxonomia.
func IsValidEquipment(v string) bool { return contains(EquipmentTypes, v) }

// IsValidLevel diz se o nível é um dos três aceitos pelo CHECK da tabela.
func IsValidLevel(v Level) bool {
	return v == LevelBeginner || v == LevelIntermediate || v == LevelAdvanced
}

func contains(list []string, v string) bool {
	for _, item := range list {
		if item == v {
			return true
		}
	}
	return false
}

// LocaleSource é a língua-fonte do conteúdo (ADR-011 §1): é o que está na
// coluna `exercises.name`, usada quando não há nenhuma tradução cadastrada.
const LocaleSource = LocalePtBR

// ParseLocale normaliza o que chega do cliente ("pt_BR", "pt-br", "pt", "en-US")
// para um dos três locales suportados. Devolve false para o resto — quem
// chama decide entre recusar (query param) ou cair no default (claim).
func ParseLocale(v string) (Locale, bool) {
	normalized := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(v), "_", "-"))
	switch {
	case normalized == "pt-pt":
		return LocalePtPT, true
	case normalized == "pt-br", normalized == "pt":
		return LocalePtBR, true
	case normalized == "en" || strings.HasPrefix(normalized, "en-"):
		return LocaleEN, true
	default:
		return "", false
	}
}

// LocaleChain é a ordem de fallback da leitura de conteúdo dinâmico: o locale
// pedido primeiro, depois os demais na ordem pt-BR → pt-PT → en.
//
// Para pt-PT dá exatamente a cascata normativa do ADR-011 §2
// (pt-PT → pt-BR → en). Para os outros dois a regra é a mesma ideia levada a
// sério: preferir o português antes do inglês, porque um nome de exercício em
// pt-PT é mais legível para um brasileiro do que em inglês. Depois disso
// ainda existe o último recurso, que não é tradução nenhuma: a coluna
// `exercises.name`, que está na língua-fonte.
func LocaleChain(locale Locale) []Locale {
	chain := []Locale{locale}
	for _, candidate := range []Locale{LocalePtBR, LocalePtPT, LocaleEN} {
		if candidate != locale {
			chain = append(chain, candidate)
		}
	}
	return chain
}

// ExerciseFilter são os filtros da listagem da biblioteca (P1.3). Campos
// vazios não filtram.
type ExerciseFilter struct {
	Query         string
	PrimaryMuscle string
	Equipment     string
	Level         Level
	Locale        Locale
	// Cursor de paginação keyset: a última linha da página anterior.
	CursorName string
	CursorID   string
	Limit      int
}

// ExerciseListItem é o exercício já resolvido no locale do usuário: o nome e
// as instruções vêm da melhor tradução disponível (LocaleChain) ou da coluna
// canônica.
type ExerciseListItem struct {
	Exercise
	// DisplayName e Instructions no locale efetivamente encontrado —
	// DisplayName não sombreia Exercise.Name de propósito: a coluna canônica
	// continua acessível e as duas nunca se confundem no handler.
	DisplayName  string
	Instructions string
	NameLocale   Locale
	// SortKey é o nome normalizado que ordena a listagem — vira cursor.
	SortKey string
}

// IsGlobal diz se o exercício é da biblioteca global da Lyfta (ADR-010 §3):
// legível por todo tenant, editável por nenhum.
func (e Exercise) IsGlobal() bool { return e.TenantID == "" }
