package repo

// nullString converte string vazia em NULL — a coluna `notes`, opcional nas
// três tabelas, distingue "sem observação" de string vazia (mesmo helper do
// workout, duplicado de propósito — ADR-013 §2).
func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}
