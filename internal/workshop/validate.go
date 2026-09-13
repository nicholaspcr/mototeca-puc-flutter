package workshop

import (
	"fmt"
	"strings"
	"unicode/utf8"

	"mototeca-backend/internal/auth"
)

const (
	cnpjDigits       = 14
	maxNameLength    = 120
	maxAddressLength = 300
)

// NormalizeCNPJ strips the punctuation Brazilians type (00.000.000/0000-00)
// so the stored value is always 14 bare digits.
func NormalizeCNPJ(raw string) string {
	var b strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ValidateCNPJ checks length and the two check digits, so an obviously bogus
// number is rejected before it reaches the database. It does NOT prove the
// company exists — that is what the `verified` flag is for.
func ValidateCNPJ(cnpj string) error {
	if len(cnpj) != cnpjDigits {
		return fmt.Errorf("CNPJ deve ter %d dígitos", cnpjDigits)
	}
	// All-identical digits pass the check-digit maths but are never real.
	if strings.Count(cnpj, string(cnpj[0])) == cnpjDigits {
		return fmt.Errorf("CNPJ inválido")
	}

	digits := make([]int, cnpjDigits)
	for i, r := range cnpj {
		digits[i] = int(r - '0')
	}

	firstWeights := []int{5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2}
	secondWeights := []int{6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2}
	if digits[12] != checkDigit(digits[:12], firstWeights) ||
		digits[13] != checkDigit(digits[:13], secondWeights) {
		return fmt.Errorf("CNPJ inválido")
	}
	return nil
}

func checkDigit(digits []int, weights []int) int {
	sum := 0
	for i, d := range digits {
		sum += d * weights[i]
	}
	if remainder := sum % 11; remainder >= 2 {
		return 11 - remainder
	}
	return 0
}

func (input CreateInput) Validate() error {
	if err := ValidateCNPJ(NormalizeCNPJ(input.CNPJ)); err != nil {
		return err
	}
	if name := strings.TrimSpace(input.Name); name == "" || utf8.RuneCountInString(name) > maxNameLength {
		return fmt.Errorf("nome é obrigatório (até %d caracteres)", maxNameLength)
	}
	if input.Address != nil && utf8.RuneCountInString(*input.Address) > maxAddressLength {
		return fmt.Errorf("endereço deve ter até %d caracteres", maxAddressLength)
	}
	return auth.ValidatePassword(input.Password)
}
