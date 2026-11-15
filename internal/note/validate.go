package note

import (
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

const (
	maxDescriptionLength = 500
	maxMileageKm         = 2_000_000
	maxCostCents         = 100_000_000
)

// Validate checks the input and returns the parsed day. now bounds the day,
// with a day of slack for owners east of the server's clock.
func (input AddInput) Validate(now time.Time) (time.Time, error) {
	if uuid.Validate(input.ClientID) != nil {
		return time.Time{}, fmt.Errorf("identificador da anotação inválido")
	}
	description := strings.TrimSpace(input.Description)
	if description == "" || utf8.RuneCountInString(description) > maxDescriptionLength {
		return time.Time{}, fmt.Errorf("descreva o que foi feito (até %d caracteres)", maxDescriptionLength)
	}
	doneOn, err := time.Parse(DateLayout, input.DoneOn)
	if err != nil {
		return time.Time{}, fmt.Errorf("data inválida")
	}
	if doneOn.After(now.AddDate(0, 0, 1)) {
		return time.Time{}, fmt.Errorf("a data não pode estar no futuro")
	}
	if input.MileageKm != nil && (*input.MileageKm < 0 || *input.MileageKm > maxMileageKm) {
		return time.Time{}, fmt.Errorf("quilometragem deve estar entre 0 e %d km", maxMileageKm)
	}
	if input.CostCents != nil && (*input.CostCents < 0 || *input.CostCents > maxCostCents) {
		return time.Time{}, fmt.Errorf("valor fora do limite")
	}
	return doneOn, nil
}
