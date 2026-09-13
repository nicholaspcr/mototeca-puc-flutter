package vehicle

import (
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	// Both plate formats used in Brazil after stripping the separator:
	// old-style (ABC1234) and Mercosul (ABC1D23).
	plateRegex  = regexp.MustCompile(`^[A-Z]{3}\d[A-Z0-9]\d{2}$`)
	chassiRegex = regexp.MustCompile(`^[A-Z0-9]{17}$`)
)

const maxNameLength = 60

var plateSeparators = strings.NewReplacer("-", "", " ", "")

func NormalizePlate(raw string) string {
	return strings.ToUpper(plateSeparators.Replace(raw))
}

// Normalized returns the input the way it is stored.
func (input CreateInput) Normalized() CreateInput {
	return CreateInput{
		Plate:  NormalizePlate(input.Plate),
		Chassi: strings.ToUpper(strings.TrimSpace(input.Chassi)),
		Make:   strings.TrimSpace(input.Make),
		Model:  strings.TrimSpace(input.Model),
		Year:   input.Year,
	}
}

// Validate expects Normalized input.
func (input CreateInput) Validate() error {
	if !plateRegex.MatchString(input.Plate) {
		return fmt.Errorf("placa inválida: use o formato ABC1234 ou ABC1D23")
	}
	if !chassiRegex.MatchString(input.Chassi) {
		return fmt.Errorf("chassi deve ter 17 letras ou números")
	}
	if input.Make == "" || utf8.RuneCountInString(input.Make) > maxNameLength {
		return fmt.Errorf("marca é obrigatória (até %d caracteres)", maxNameLength)
	}
	if input.Model == "" || utf8.RuneCountInString(input.Model) > maxNameLength {
		return fmt.Errorf("modelo é obrigatório (até %d caracteres)", maxNameLength)
	}
	currentYear := time.Now().Year()
	if input.Year < 1950 || input.Year > currentYear+1 {
		return fmt.Errorf("ano deve estar entre 1950 e %d", currentYear+1)
	}
	return nil
}
