package http

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/billing/internal/repo"
)

func invoiceError(err error) (APIError, bool) {
	switch {
	case errors.Is(err, repo.ErrInvoiceAlreadyPaid):
		return errInvoiceAlreadyPaid(), true
	case errors.Is(err, repo.ErrInvoiceCanceled):
		return errInvoiceCanceled(), true
	case errors.Is(err, repo.ErrPaymentAlreadyReversed):
		return errPaymentAlreadyReversed(), true
	case errors.Is(err, repo.ErrPaymentIsReversal):
		return errPaymentIsReversal(), true
	case errors.Is(err, repo.ErrIdempotencyConflict):
		return errIdempotencyConflict(), true
	}
	return APIError{}, false
}

func parseLimit(r *http.Request) int {
	n, err := strconv.Atoi(r.URL.Query().Get("limit"))
	if err != nil || n <= 0 || n > repo.MaxInvoicePage {
		return 50
	}
	return n
}

// ListInvoices — GET /v1/billing/invoices?status=&period=&student_id=&cursor=&limit=
// O coach (`own_students`) só vê as faturas dos alunos do vínculo.
func (h *BillingHandler) ListInvoices(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	q := r.URL.Query()
	f := repo.InvoiceFilter{Status: q.Get("status"), Period: q.Get("period"), StudentID: q.Get("student_id"), Limit: parseLimit(r)}
	if f.Status != "" && !statusRe.MatchString(f.Status) {
		writeError(w, errValidation("status"))
		return
	}
	if f.Period != "" && !periodRe.MatchString(f.Period) {
		writeError(w, errValidation("period"))
		return
	}
	if f.StudentID != "" {
		if _, err := uuid.Parse(f.StudentID); err != nil {
			writeError(w, errValidation("student_id"))
			return
		}
		if !h.linked(w, r, claims, f.StudentID) {
			return
		}
	}
	if raw := q.Get("cursor"); raw != "" {
		at, id, err := decodeCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		f.CursorDate, f.CursorID = at.Format(time.DateOnly), id
	}
	ids, err := h.scope(r.Context(), claims)
	if err != nil {
		h.fail(w, "coach_link_check_failed", err)
		return
	}
	f.StudentIDs = ids
	h.writeInvoicePage(w, r, claims.TenantID, f, false)
}

func (h *BillingHandler) writeInvoicePage(w http.ResponseWriter, r *http.Request, tenantID string, f repo.InvoiceFilter, forStudent bool) {
	items, hasMore, err := h.invoices.List(r.Context(), tenantID, f)
	if err != nil {
		h.fail(w, "billing_invoices_list_failed", err)
		return
	}
	next := ""
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		if at, perr := time.Parse(time.DateOnly, last.DueDate); perr == nil {
			next = encodeCursor(at, last.ID)
		}
	}
	var payload any = items
	if forStudent {
		out := make([]myInvoice, 0, len(items))
		for _, i := range items {
			out = append(out, myInvoice{ID: i.ID, Period: i.Period, DueDate: i.DueDate, AmountCents: i.AmountCents,
				Currency: i.Currency, Status: i.Status, PaidAt: i.PaidAt})
		}
		payload = out
	}
	resp := map[string]any{"items": payload}
	if next != "" {
		resp["next_cursor"] = next
	}
	writeJSON(w, http.StatusOK, resp)
}

// myInvoice é a visão do aluno: somente leitura, sem dados do titular nem
// pagamentos (a `note` da baixa é interna do financeiro).
type myInvoice struct {
	ID          string     `json:"id"`
	Period      string     `json:"period"`
	DueDate     string     `json:"due_date"`
	AmountCents int64      `json:"amount_cents"`
	Currency    string     `json:"currency"`
	Status      string     `json:"status"`
	PaidAt      *time.Time `json:"paid_at"`
}

// MyInvoices — GET /v1/me/invoices: as faturas do próprio usuário.
func (h *BillingHandler) MyInvoices(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	if _, err := uuid.Parse(claims.Subject); err != nil {
		writeError(w, errUnauthenticated())
		return
	}
	f := repo.InvoiceFilter{StudentID: claims.Subject, Limit: parseLimit(r)}
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		at, id, err := decodeCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		f.CursorDate, f.CursorID = at.Format(time.DateOnly), id
	}
	h.writeInvoicePage(w, r, claims.TenantID, f, true)
}

// loadInvoice carrega a fatura e aplica o vínculo do coach.
func (h *BillingHandler) loadInvoice(w http.ResponseWriter, r *http.Request) (repo.Invoice, bool) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return repo.Invoice{}, false
	}
	inv, err := h.invoices.Get(r.Context(), claims.TenantID, id)
	if isNotFound(err) {
		writeError(w, errNotFound("invoice"))
		return repo.Invoice{}, false
	}
	if err != nil {
		h.fail(w, "billing_invoice_get_failed", err)
		return repo.Invoice{}, false
	}
	if !h.linked(w, r, claims, inv.StudentID) {
		return repo.Invoice{}, false
	}
	return inv, true
}

// GetInvoice — GET /v1/billing/invoices/{id}: com o histórico de pagamentos.
func (h *BillingHandler) GetInvoice(w http.ResponseWriter, r *http.Request) {
	if inv, ok := h.loadInvoice(w, r); ok {
		writeJSON(w, http.StatusOK, inv)
	}
}

// CancelInvoice — POST /v1/billing/invoices/{id}/cancel (owner). Fatura paga
// não cancela (estorne antes).
func (h *BillingHandler) CancelInvoice(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	inv, err := h.invoices.Cancel(r.Context(), claims.TenantID, id)
	if isNotFound(err) {
		writeError(w, errNotFound("invoice"))
		return
	}
	if err != nil {
		if apiErr, known := invoiceError(err); known {
			writeError(w, apiErr)
			return
		}
		h.fail(w, "billing_invoice_cancel_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, inv)
}

type paymentRequest struct {
	PaidAt string  `json:"paid_at"`
	Note   *string `json:"note"`
}

// parsePaidAt aceita RFC 3339 ou só a data (AAAA-MM-DD, no fuso do tenant).
// Vazio = agora. Data futura é inválida; "só a data" vira meio-dia local,
// limitado ao instante atual (não cria baixa no futuro).
func parsePaidAt(raw string, now time.Time, today time.Time, loc *time.Location) (time.Time, bool) {
	if raw == "" {
		return now, true
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		if t.After(now.Add(5 * time.Minute)) {
			return time.Time{}, false
		}
		return t, true
	}
	d, err := time.Parse(time.DateOnly, raw)
	if err != nil || d.After(today) {
		return time.Time{}, false
	}
	noon := time.Date(d.Year(), d.Month(), d.Day(), 12, 0, 0, 0, loc)
	if noon.After(now) {
		noon = now
	}
	return noon, true
}

// RecordPayment — POST /v1/billing/invoices/{id}/payments: baixa manual,
// sempre pelo valor integral. `Idempotency-Key` repetido na mesma fatura
// devolve o mesmo pagamento (200 em vez de 201); fatura já paga sem chave
// (ou com outra) = 409 `invoice_already_paid`.
func (h *BillingHandler) RecordPayment(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	inv, ok := h.loadInvoice(w, r)
	if !ok {
		return
	}
	var req paymentRequest
	if !decodeBody(w, r, &req) {
		return
	}
	note, valid := cleanNote(req.Note, false)
	if !valid {
		writeError(w, errValidation("note"))
		return
	}
	var key *string
	if raw := trimmed(r.Header.Get("Idempotency-Key")); raw != "" {
		if len(raw) > 200 {
			writeError(w, errValidation("Idempotency-Key"))
			return
		}
		key = &raw
	}
	today, loc, ok := h.today(w, r.Context(), claims.TenantID)
	if !ok {
		return
	}
	paidAt, valid := parsePaidAt(trimmed(req.PaidAt), h.now(), today, loc)
	if !valid {
		writeError(w, errValidation("paid_at"))
		return
	}

	pay, updated, replay, err := h.invoices.RecordPayment(r.Context(), claims.TenantID, repo.RecordPaymentInput{
		InvoiceID: inv.ID, RecordedBy: claims.Subject, PaidAt: paidAt, Note: note, IdempotencyKey: key,
	})
	if isNotFound(err) {
		writeError(w, errNotFound("invoice"))
		return
	}
	if err != nil {
		if apiErr, known := invoiceError(err); known {
			writeError(w, apiErr)
			return
		}
		h.fail(w, "billing_payment_failed", err)
		return
	}
	status := http.StatusCreated
	if replay {
		status = http.StatusOK
	}
	writeJSON(w, status, map[string]any{"payment": pay, "invoice": updated})
}

type reverseRequest struct {
	Note *string `json:"note"`
}

// ReversePayment — POST /v1/billing/payments/{id}/reverse (owner): estorno
// com motivo obrigatório. Estornar duas vezes = 409 `payment_already_reversed`.
func (h *BillingHandler) ReversePayment(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req reverseRequest
	if !decodeBody(w, r, &req) {
		return
	}
	note, valid := cleanNote(req.Note, true)
	if !valid {
		writeError(w, errValidation("note"))
		return
	}
	today, _, ok := h.today(w, r.Context(), claims.TenantID)
	if !ok {
		return
	}
	reversal, inv, err := h.invoices.ReversePayment(r.Context(), claims.TenantID, id, claims.Subject, *note, today)
	if isNotFound(err) {
		writeError(w, errNotFound("payment"))
		return
	}
	if err != nil {
		if apiErr, known := invoiceError(err); known {
			writeError(w, apiErr)
			return
		}
		h.fail(w, "billing_reversal_failed", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment": reversal, "invoice": inv})
}

// cleanNote normaliza a observação: vazia vira nil (ou inválida se
// obrigatória); acima de maxNoteLen é inválida.
func cleanNote(note *string, required bool) (*string, bool) {
	if note == nil || trimmed(*note) == "" {
		return nil, !required
	}
	n := trimmed(*note)
	if len([]rune(n)) > maxNoteLen {
		return nil, false
	}
	return &n, true
}

const maxStatusIDs = 200

// StudentStatuses — GET /v1/billing/students/status?ids=a,b,c →
// {id: ok|delinquent|none}, sem valores. O coach só recebe os alunos do
// vínculo (ADR-016): os demais ids ficam de fora da resposta.
func (h *BillingHandler) StudentStatuses(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	raw := strings.TrimSpace(r.URL.Query().Get("ids"))
	if raw == "" {
		writeError(w, errValidation("ids"))
		return
	}
	parts := strings.Split(raw, ",")
	if len(parts) > maxStatusIDs {
		writeError(w, errValidation("ids"))
		return
	}
	seen := map[string]struct{}{}
	ids := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if _, err := uuid.Parse(p); err != nil {
			writeError(w, errValidation("ids"))
			return
		}
		if _, dup := seen[p]; !dup {
			seen[p] = struct{}{}
			ids = append(ids, p)
		}
	}
	if !hasRole(claims, "owner") {
		set, err := h.linker.StudentsOf(r.Context(), claims.TenantID, claims.Subject)
		if err != nil {
			h.fail(w, "coach_link_check_failed", err)
			return
		}
		allowed := ids[:0]
		for _, id := range ids {
			if _, ok := set[id]; ok {
				allowed = append(allowed, id)
			}
		}
		ids = allowed
	}
	statuses, err := h.invoices.StudentStatuses(r.Context(), claims.TenantID, ids)
	if err != nil {
		h.fail(w, "billing_status_failed", err)
		return
	}
	writeJSON(w, http.StatusOK, statuses)
}
