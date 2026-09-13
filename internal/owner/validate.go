package owner

import (
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"

	"mototeca-backend/internal/auth"
)

const (
	maxNameLength      = 120
	ChassiSuffixLength = 6
)

var chassiSuffixRegex = regexp.MustCompile(fmt.Sprintf(`^[A-Z0-9]{%d}$`, ChassiSuffixLength))

// NormalizeChassiSuffix upper-cases and trims what the owner typed.
func NormalizeChassiSuffix(raw string) string {
	return strings.ToUpper(strings.TrimSpace(raw))
}

func ValidateChassiSuffix(suffix string) error {
	if !chassiSuffixRegex.MatchString(suffix) {
		return fmt.Errorf("informe os %d últimos caracteres do chassi", ChassiSuffixLength)
	}
	return nil
}

// NormalizePhone strips the punctuation people type into a phone field
// ((31) 90000-0000) so the stored value is always bare digits.
func NormalizePhone(raw string) string {
	var b strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ValidatePhone accepts a Brazilian number with area code: 10 digits for a
// landline, 11 for a mobile (which must have the leading 9).
func ValidatePhone(phone string) error {
	switch len(phone) {
	case 10:
		return nil
	case 11:
		if phone[2] != '9' {
			return fmt.Errorf("celular com 11 dígitos deve começar com 9 após o DDD")
		}
		return nil
	default:
		return fmt.Errorf("telefone deve ter 10 ou 11 dígitos com DDD")
	}
}

func (input CreateInput) Validate() error {
	if name := strings.TrimSpace(input.Name); name == "" || utf8.RuneCountInString(name) > maxNameLength {
		return fmt.Errorf("nome é obrigatório (até %d caracteres)", maxNameLength)
	}
	if err := ValidatePhone(NormalizePhone(input.Phone)); err != nil {
		return err
	}
	return auth.ValidatePassword(input.Password)
}
