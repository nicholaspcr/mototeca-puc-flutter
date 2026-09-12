package servicerecord

import (
	"fmt"
	"strings"
)

// Bounds that keep obvious nonsense out of the history. maxMileageKm is far
// past any real motorcycle's odometer; maxCostCents is R$ 1.000.000,00.
const (
	maxMileageKm   = 2_000_000
	maxCostCents   = 100_000_000
	maxNotesLength = 2000
	maxParts       = 50
	maxPartName    = 200
	maxPartQty     = 1000
)

func (input CreateInput) Validate() error {
	if input.WorkshopID == "" {
		return fmt.Errorf("workshop is required")
	}
	if len(input.Operations) == 0 {
		return fmt.Errorf("select at least one operation")
	}

	seen := make(map[Operation]bool, len(input.Operations))
	for _, op := range input.Operations {
		if !op.Valid() {
			return fmt.Errorf("unknown operation %q", op)
		}
		if seen[op] {
			return fmt.Errorf("operation %q is listed twice", op)
		}
		seen[op] = true
	}

	if input.MileageKm < 0 || input.MileageKm > maxMileageKm {
		return fmt.Errorf("mileage must be between 0 and %d km", maxMileageKm)
	}
	if input.CostCents != nil && (*input.CostCents < 0 || *input.CostCents > maxCostCents) {
		return fmt.Errorf("cost is out of range")
	}
	if input.Notes != nil && len(*input.Notes) > maxNotesLength {
		return fmt.Errorf("notes must be at most %d characters", maxNotesLength)
	}
	if input.MechanicName != nil && strings.TrimSpace(*input.MechanicName) == "" {
		return fmt.Errorf("mechanic name must not be blank")
	}

	if len(input.Parts) > maxParts {
		return fmt.Errorf("a record may list at most %d parts", maxParts)
	}
	for i, part := range input.Parts {
		if strings.TrimSpace(part.Name) == "" {
			return fmt.Errorf("part %d: name is required", i+1)
		}
		if len(part.Name) > maxPartName {
			return fmt.Errorf("part %d: name is too long", i+1)
		}
		if part.Quantity < 1 || part.Quantity > maxPartQty {
			return fmt.Errorf("part %d: quantity must be between 1 and %d", i+1, maxPartQty)
		}
		if part.CostCents != nil && (*part.CostCents < 0 || *part.CostCents > maxCostCents) {
			return fmt.Errorf("part %d: cost is out of range", i+1)
		}
	}

	return nil
}
