package http

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/marcus-coube/lyfta/comms/internal/domain"
	"github.com/marcus-coube/lyfta/comms/internal/repo"
)

// DeviceHandler expõe o registro de token de push (P3.4, passo 1): o app
// chama isto no boot/login e sempre que o token do FCM mudar.
type DeviceHandler struct {
	logger *slog.Logger
	tokens *repo.DeviceTokenRepo
}

// NewDeviceHandler cria o handler de device tokens.
func NewDeviceHandler(logger *slog.Logger, tokens *repo.DeviceTokenRepo) *DeviceHandler {
	return &DeviceHandler{logger: logger, tokens: tokens}
}

type deviceTokenDTO struct {
	ID        string    `json:"id"`
	Platform  string    `json:"platform"`
	Locale    string    `json:"locale"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Register faz upsert do token do device autenticado (tenant+user+platform,
// migration 0004) — o `user_id` vem sempre da claim, nunca do corpo (mesmo
// critério do resto do serviço: quem registra o próprio device é sempre
// quem está autenticado, nunca em nome de outro usuário). O locale é o que o
// app manda AGORA: é o que a P3.4 usa para renderizar o texto do push desse
// device, tanto nos eventos em tempo real quanto no job diário (ver Notas de
// execução da P3.4 — não há claim de locale disponível fora de uma
// requisição HTTP do próprio destinatário).
func (h *DeviceHandler) Register(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	var req struct {
		Platform string `json:"platform"`
		Token    string `json:"token"`
		Locale   string `json:"locale"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, errInvalidBody())
		return
	}

	platform := domain.DevicePlatform(strings.TrimSpace(req.Platform))
	if !domain.IsValidPlatform(platform) {
		writeError(w, errValidation("platform"))
		return
	}
	token := strings.TrimSpace(req.Token)
	if token == "" {
		writeError(w, errValidation("token"))
		return
	}
	locale := strings.TrimSpace(req.Locale)
	if !domain.IsValidLocale(locale) {
		writeError(w, errValidation("locale"))
		return
	}

	saved, err := h.tokens.Upsert(r.Context(), claims.TenantID, claims.Subject, platform, token, locale)
	if err != nil {
		h.logger.Error("device_register_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	writeJSON(w, http.StatusOK, deviceTokenDTO{
		ID: saved.ID, Platform: string(saved.Platform), Locale: saved.Locale, UpdatedAt: saved.UpdatedAt,
	})
}
