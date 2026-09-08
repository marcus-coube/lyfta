package http

import (
	"encoding/base64"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// encodeCursor/decodeCursor empacotam o keyset (timestamp + id) do histórico
// de mensagens num token opaco — mesmo formato do cursor do assessment
// (ADR-013 §2, duplicado), mas com precisão de instante (RFC3339Nano) em vez
// de dia: mensagens acontecem várias por segundo, uma medida corporal não.
const cursorSeparator = "\x1f"

func encodeCursor(at time.Time, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(at.UTC().Format(time.RFC3339Nano) + cursorSeparator + id))
}

func decodeCursor(raw string) (at time.Time, id string, err error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return time.Time{}, "", err
	}
	parts := strings.SplitN(string(decoded), cursorSeparator, 2)
	if len(parts) != 2 || parts[1] == "" {
		return time.Time{}, "", errors.New("http: cursor malformado")
	}
	at, err = time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", err
	}
	if _, err := uuid.Parse(parts[1]); err != nil {
		return time.Time{}, "", err
	}
	return at, parts[1], nil
}

// parseListQuery lê `cursor` e `limit` da listagem de mensagens.
func parseListQuery(r *http.Request) (cursorAt *time.Time, cursorID string, limit int, apiErr *APIError) {
	q := r.URL.Query()
	if raw := q.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			return nil, "", 0, fail("limit")
		}
		limit = parsed
	}
	if raw := strings.TrimSpace(q.Get("cursor")); raw != "" {
		at, id, err := decodeCursor(raw)
		if err != nil {
			apiErr := errInvalidCursor()
			return nil, "", 0, &apiErr
		}
		cursorAt, cursorID = &at, id
	}
	return cursorAt, cursorID, limit, nil
}

func fail(field string) *APIError {
	apiErr := errValidation(field)
	return &apiErr
}
