package repo

import "errors"

// ErrNotFound é devolvido pelos repositórios quando a busca não encontra
// nenhum registro (após RLS filtrar o resultado, inclusive).
var ErrNotFound = errors.New("repo: registro não encontrado")

// Erros de regra de negócio do financeiro; o handler traduz cada um num
// `code` estável (ADR-011 §3).
var (
	ErrPlanArchived           = errors.New("repo: plano de mensalidade arquivado")
	ErrSubscriptionExists     = errors.New("repo: aluno já tem assinatura ativa ou pausada")
	ErrInvalidState           = errors.New("repo: transição de estado inválida")
	ErrInvoiceAlreadyPaid     = errors.New("repo: fatura já paga")
	ErrInvoiceCanceled        = errors.New("repo: fatura cancelada")
	ErrPaymentAlreadyReversed = errors.New("repo: pagamento já estornado")
	ErrPaymentIsReversal      = errors.New("repo: estorno não pode ser estornado")
	ErrIdempotencyConflict    = errors.New("repo: Idempotency-Key já usada em outra fatura")
)
