package repo

// nullString converte string vazia em NULL — mesmo helper do workout/
// assessment, duplicado de propósito (ADR-013 §2).
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}
