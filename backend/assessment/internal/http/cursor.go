package http

import (
	"encoding/base64"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

// encodeCursor/decodeCursor empacotam o keyset (data + id) das três
// listagens num token opaco — mesmo formato do cursor da biblioteca/histórico
// do workout (ADR-013 §2, duplicado). O cliente devolve o que recebeu, e a
// composição da chave pode mudar sem quebrar contrato.
const cursorSeparator = "\x1f"

func encodeCursor(at time.Time, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(at.Format(time.DateOnly) + cursorSeparator + id))
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
	at, err = time.Parse(time.DateOnly, parts[0])
	if err != nil {
		return time.Time{}, "", err
	}
	if _, err := uuid.Parse(parts[1]); err != nil {
		return time.Time{}, "", err
	}
	return at, parts[1], nil
}
