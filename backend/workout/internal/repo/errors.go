package repo

import "errors"

// ErrNotFound é devolvido pelos repositórios quando a busca não encontra
// nenhum registro (após RLS filtrar o resultado, inclusive).
var ErrNotFound = errors.New("repo: registro não encontrado")
