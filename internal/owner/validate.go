package owner

import (
	"fmt"
	"strings"

	"mototeca-backend/internal/auth"
)

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
	if strings.TrimSpace(input.Name) == "" {
		return fmt.Errorf("name is required")
	}
	if err := ValidatePhone(NormalizePhone(input.Phone)); err != nil {
		return err
	}
	return auth.ValidatePassword(input.Password)
}
