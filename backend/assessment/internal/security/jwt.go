// Package security valida os access tokens emitidos pelo identity.
//
// O assessment é apenas verificador: assina token quem tem a chave privada, e
// isso é exclusividade do identity (ADR-013 §4). Este pacote é irmão do
// internal/security do identity e do workout, duplicado de propósito —
// serviços não importam código uns dos outros (ADR-013 §2).
package security

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"

	"github.com/golang-jwt/jwt/v5"
)

// ErrInvalidToken cobre token malformado, assinatura inválida ou expirado — o
// handler traduz para 401 sem detalhar o motivo exato.
var ErrInvalidToken = errors.New("security: token inválido ou expirado")

// Claims é o payload do access token JWT emitido pelo identity (ADR-002).
type Claims struct {
	jwt.RegisteredClaims
	TenantID string   `json:"tenant_id"`
	Roles    []string `json:"roles"`
	Locale   string   `json:"locale"`
	// Consents são as finalidades de consentimento vigentes na versão atual
	// dos termos (ADR-008 §1, P4.5): o assessment checa `progress_photos` aqui
	// para o aluno agir sobre as próprias fotos, sem chamada ao identity.
	Consents []string `json:"consents"`
}

// HasConsent diz se a finalidade está vigente nas claims.
func (c *Claims) HasConsent(purpose string) bool {
	for _, p := range c.Consents {
		if p == purpose {
			return true
		}
	}
	return false
}

// JWTVerifier valida access tokens EdDSA (ed25519) com a chave pública.
type JWTVerifier struct {
	public ed25519.PublicKey
}

// NewJWTVerifier decodifica a chave pública ed25519 do PEM (env
// JWT_PUBLIC_KEY, gerada por backend/scripts/gen-keys.sh).
func NewJWTVerifier(publicPEM string) (*JWTVerifier, error) {
	pub, err := parsePublicKey(publicPEM)
	if err != nil {
		return nil, fmt.Errorf("security: chave pública JWT: %w", err)
	}
	return &JWTVerifier{public: pub}, nil
}

// Parse valida assinatura e expiração e devolve as claims. Qualquer falha
// (assinatura, exp, formato, algoritmo trocado) vira ErrInvalidToken.
func (v *JWTVerifier) Parse(tokenString string) (*Claims, error) {
	if v.public == nil {
		return nil, errors.New("security: verifier sem chave pública")
	}

	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodEd25519); !ok {
			return nil, ErrInvalidToken
		}
		return v.public, nil
	})
	if err != nil || !token.Valid {
		return nil, ErrInvalidToken
	}
	return claims, nil
}

func parsePublicKey(pemStr string) (ed25519.PublicKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, errors.New("PEM inválido")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	pub, ok := key.(ed25519.PublicKey)
	if !ok {
		return nil, errors.New("chave pública não é ed25519")
	}
	return pub, nil
}
