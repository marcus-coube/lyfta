package security

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// AccessTokenTTL é a validade do access token (P0.3: 15 minutos).
const AccessTokenTTL = 15 * time.Minute

// ErrInvalidToken cobre token malformado, assinatura inválida ou expirado —
// o handler traduz para 401 code:invalid_token sem detalhar o motivo exato.
var ErrInvalidToken = errors.New("security: token inválido ou expirado")

// Claims é o payload do access token JWT (backend/README.md: EdDSA,
// claims sub/tenant_id/roles/locale/exp).
type Claims struct {
	jwt.RegisteredClaims
	TenantID string   `json:"tenant_id"`
	Roles    []string `json:"roles"`
	Locale   string   `json:"locale"`
	// Timezone é o fuso IANA do tenant (ADR-007 §3, P5.1): os serviços que
	// precisam de dia civil usam esta claim em vez do relógio do servidor.
	Timezone string `json:"tz"`
	// Consents são as finalidades de consentimento vigentes na versão atual
	// dos termos (ADR-008 §1, P4.5) — os outros serviços checam aqui, sem
	// chamada síncrona ao identity.
	Consents []string `json:"consents"`
}

// JWTSigner assina e valida access tokens EdDSA (ed25519).
type JWTSigner struct {
	private ed25519.PrivateKey
	public  ed25519.PublicKey
}

// NewJWTSigner decodifica o par de chaves ed25519 a partir dos PEMs (env
// JWT_PRIVATE_KEY/JWT_PUBLIC_KEY, gerados por backend/scripts/gen-keys.sh).
// privatePEM pode ser vazio para um signer só de validação (demais serviços).
func NewJWTSigner(privatePEM, publicPEM string) (*JWTSigner, error) {
	s := &JWTSigner{}

	if publicPEM != "" {
		pub, err := parsePublicKey(publicPEM)
		if err != nil {
			return nil, fmt.Errorf("security: chave pública JWT: %w", err)
		}
		s.public = pub
	}

	if privatePEM != "" {
		priv, err := parsePrivateKey(privatePEM)
		if err != nil {
			return nil, fmt.Errorf("security: chave privada JWT: %w", err)
		}
		s.private = priv
		if s.public == nil {
			s.public = priv.Public().(ed25519.PublicKey)
		}
	}

	return s, nil
}

// Sign emite um access token para o usuário/tenant/papéis informados.
func (s *JWTSigner) Sign(userID, tenantID string, roles []string, locale, timezone string, consents []string) (string, time.Time, error) {
	return s.SignWithExpiry(userID, tenantID, roles, locale, timezone, consents, time.Now().Add(AccessTokenTTL))
}

// SignWithExpiry emite um access token com expiração explícita — usado por
// Sign (TTL padrão de 15min) e por testes que precisam simular um token já
// expirado.
func (s *JWTSigner) SignWithExpiry(userID, tenantID string, roles []string, locale, timezone string, consents []string, expiresAt time.Time) (string, time.Time, error) {
	if s.private == nil {
		return "", time.Time{}, errors.New("security: signer sem chave privada")
	}
	now := time.Now()

	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
		TenantID: tenantID,
		Roles:    roles,
		Locale:   locale,
		Timezone: timezone,
		Consents: consents,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims)
	signed, err := token.SignedString(s.private)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("security: assinar token: %w", err)
	}
	return signed, expiresAt, nil
}

// Parse valida a assinatura e a expiração de um access token e devolve as
// claims. Qualquer falha (assinatura, exp, formato) vira ErrInvalidToken.
func (s *JWTSigner) Parse(tokenString string) (*Claims, error) {
	if s.public == nil {
		return nil, errors.New("security: signer sem chave pública")
	}

	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodEd25519); !ok {
			return nil, ErrInvalidToken
		}
		return s.public, nil
	})
	if err != nil || !token.Valid {
		return nil, ErrInvalidToken
	}
	return claims, nil
}

func parsePrivateKey(pemStr string) (ed25519.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, errors.New("PEM inválido")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	priv, ok := key.(ed25519.PrivateKey)
	if !ok {
		return nil, errors.New("chave privada não é ed25519")
	}
	return priv, nil
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
