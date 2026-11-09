package repo

import "errors"

// ErrNotFound é devolvido pelos repositórios quando a busca não encontra
// nenhum registro (após RLS filtrar o resultado, inclusive).
var ErrNotFound = errors.New("repo: registro não encontrado")

// Erros da mudança de status do aluno (P5.2): o handler os traduz em 409.
var (
	// ErrAlreadyInStatus: o aluno já está no status pedido.
	ErrAlreadyInStatus = errors.New("repo: aluno já está nesse status")
	// ErrInvalidTransition: o status atual não permite a transição (ex.:
	// inativar quem ainda não aceitou o convite).
	ErrInvalidTransition = errors.New("repo: transição de status inválida")
)
