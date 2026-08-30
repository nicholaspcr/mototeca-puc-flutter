package vehicle

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// Matches both plate formats used in Brazil after stripping the separator:
// old-style (ABC1234) and Mercosul (ABC1D23).
var plateRegex = regexp.MustCompile(`^[A-Z]{3}\d[A-Z0-9]\d{2}$`)

func NormalizePlate(raw string) string {
	return strings.ToUpper(strings.ReplaceAll(raw, "-", ""))
}

func (input CreateInput) Validate() error {
	plate := NormalizePlate(input.Plate)
	if !plateRegex.MatchString(plate) {
		return fmt.Errorf("invalid Brazilian plate format")
	}
	if len(input.Chassi) != 17 {
		return fmt.Errorf("chassi must be 17 characters")
	}
	if strings.TrimSpace(input.Make) == "" {
		return fmt.Errorf("make is required")
	}
	if strings.TrimSpace(input.Model) == "" {
		return fmt.Errorf("model is required")
	}
	currentYear := time.Now().Year()
	if input.Year < 1950 || input.Year > currentYear+1 {
		return fmt.Errorf("year must be between 1950 and %d", currentYear+1)
	}
	return nil
}
