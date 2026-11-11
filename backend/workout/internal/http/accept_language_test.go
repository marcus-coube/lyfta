package http

import (
	"testing"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
)

func TestAcceptLanguageLocale(t *testing.T) {
	cases := []struct {
		header string
		want   domain.Locale
		ok     bool
	}{
		{"", "", false},
		{"en", domain.LocaleEN, true},
		{"en-US,en;q=0.9", domain.LocaleEN, true},
		{"pt-PT", domain.LocalePtPT, true},
		{"fr-FR,fr;q=0.9,en;q=0.5", domain.LocaleEN, true},
		{"pt-BR;q=0.5, en;q=0.8", domain.LocaleEN, true},
		{"fr, de;q=0.4", "", false},
		{"en;q=0", "", false},
		{"en;q=lixo, pt-PT", domain.LocalePtPT, true},
	}
	for _, tc := range cases {
		got, ok := acceptLanguageLocale(tc.header)
		if got != tc.want || ok != tc.ok {
			t.Errorf("%q: veio (%q,%v), esperava (%q,%v)", tc.header, got, ok, tc.want, tc.ok)
		}
	}
}
