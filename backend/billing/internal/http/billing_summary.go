package http

import (
	"net/http"
	"strings"
	"time"
)

type seriesPointDTO struct {
	Period        string `json:"period"`
	ReceivedCents int64  `json:"received_cents"`
}

type summaryResponse struct {
	Period             string           `json:"period"`
	Currency           string           `json:"currency"`
	ReceivedCents      int64            `json:"received_cents"`
	ToReceiveCents     int64            `json:"to_receive_cents"`
	ToReceiveCount     int              `json:"to_receive_count"`
	OverdueCents       int64            `json:"overdue_cents"`
	OverdueCount       int              `json:"overdue_count"`
	DelinquentStudents int              `json:"delinquent_students"`
	ReceivedSeries     []seriesPointDTO `json:"received_series"`
}

// Summary — GET /v1/billing/summary?period=AAAA-MM (P8.1, só owner): recebido
// no mês (pelo `paid_at` no fuso do tenant), a receber (abertas com vencimento
// no mês), vencido (estoque atual: valor, nº de faturas e de inadimplentes) e a
// série de recebido dos 6 meses que terminam em `period`. Sem `period` usa o
// mês corrente do tenant. Coach recebe 403 `billing_access_denied` em qualquer
// modo (ADR-017 §3: valores agregados são do owner).
func (h *BillingHandler) Summary(w http.ResponseWriter, r *http.Request) {
	claims, _ := ClaimsFromContext(r.Context())
	period := strings.TrimSpace(r.URL.Query().Get("period"))
	if period != "" && !periodRe.MatchString(period) {
		writeError(w, errValidation("period"))
		return
	}
	today, loc, ok := h.today(w, r.Context(), claims.TenantID)
	if !ok {
		return
	}
	monthStart := time.Date(today.Year(), today.Month(), 1, 0, 0, 0, 0, time.UTC)
	if period == "" {
		period = monthStart.Format("2006-01")
	} else if t, err := time.Parse("2006-01", period); err == nil {
		monthStart = t
	}
	sum, err := h.invoices.Summary(r.Context(), claims.TenantID, period, loc.String(), monthStart)
	if err != nil {
		h.fail(w, "billing_summary_failed", err)
		return
	}
	resp := summaryResponse{
		Period: sum.Period, Currency: "BRL",
		ReceivedCents: sum.ReceivedCents, ToReceiveCents: sum.ToReceiveCents, ToReceiveCount: sum.ToReceiveCount,
		OverdueCents: sum.OverdueCents, OverdueCount: sum.OverdueCount, DelinquentStudents: sum.DelinquentStudent,
		ReceivedSeries: make([]seriesPointDTO, 0, len(sum.Series)),
	}
	for _, p := range sum.Series {
		resp.ReceivedSeries = append(resp.ReceivedSeries, seriesPointDTO{Period: p.Period, ReceivedCents: p.ReceivedCents})
	}
	writeJSON(w, http.StatusOK, resp)
}
