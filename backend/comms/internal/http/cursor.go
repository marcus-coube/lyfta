package http

import (
	"encoding/base64"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/marcus-coube/lyfta/comms/internal/repo"
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

// checkinCursorNilMarker representa, no campo `reviewed_at` do cursor
// opaco, um item de referência que ainda não tinha sido revisado — não dá
// pra usar uma string vazia genérica porque o separador já delimita os
// campos; um marcador que nunca é um RFC3339Nano válido evita ambiguidade.
const checkinCursorNilMarker = "-"

// encodeCheckinCursor empacota os três campos do keyset da listagem de
// check-ins (reviewed_at + created_at + id, ver repo.CheckinCursor) — mesmo
// formato opaco em base64 do cursor de mensagens, só que com um campo a mais.
// reviewedAt nil (item de referência ainda não revisado) vira
// checkinCursorNilMarker.
func encodeCheckinCursor(reviewedAt *time.Time, createdAt time.Time, id string) string {
	reviewedAtPart := checkinCursorNilMarker
	if reviewedAt != nil {
		reviewedAtPart = reviewedAt.UTC().Format(time.RFC3339Nano)
	}
	raw := reviewedAtPart + cursorSeparator +
		createdAt.UTC().Format(time.RFC3339Nano) + cursorSeparator + id
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeCheckinCursor(raw string) (reviewedAt *time.Time, createdAt time.Time, id string, err error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return nil, time.Time{}, "", err
	}
	parts := strings.SplitN(string(decoded), cursorSeparator, 3)
	if len(parts) != 3 || parts[2] == "" {
		return nil, time.Time{}, "", errors.New("http: cursor malformado")
	}
	if parts[0] != checkinCursorNilMarker {
		at, err := time.Parse(time.RFC3339Nano, parts[0])
		if err != nil {
			return nil, time.Time{}, "", err
		}
		reviewedAt = &at
	}
	createdAt, err = time.Parse(time.RFC3339Nano, parts[1])
	if err != nil {
		return nil, time.Time{}, "", err
	}
	if _, err := uuid.Parse(parts[2]); err != nil {
		return nil, time.Time{}, "", err
	}
	return reviewedAt, createdAt, parts[2], nil
}

// parseCheckinListQuery lê `student_id` (opcional — vazio lista o tenant
// inteiro, visão do coach), `cursor` e `limit` de GET /v1/checkins.
func parseCheckinListQuery(r *http.Request) (studentID string, cursor *repo.CheckinCursor, limit int, apiErr *APIError) {
	q := r.URL.Query()
	studentID = strings.TrimSpace(q.Get("student_id"))
	if studentID != "" {
		if _, err := uuid.Parse(studentID); err != nil {
			return "", nil, 0, ptr(errValidation("student_id"))
		}
	}
	if raw := q.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			return "", nil, 0, ptr(errValidation("limit"))
		}
		limit = parsed
	}
	if raw := strings.TrimSpace(q.Get("cursor")); raw != "" {
		reviewedAt, createdAt, id, err := decodeCheckinCursor(raw)
		if err != nil {
			return "", nil, 0, ptr(errInvalidCursor())
		}
		cursor = &repo.CheckinCursor{ReviewedAt: reviewedAt, CreatedAt: createdAt, ID: id}
	}
	return studentID, cursor, limit, nil
}

func fail(field string) *APIError {
	apiErr := errValidation(field)
	return &apiErr
}
