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
		return fmt.Errorf("oficina é obrigatória")
	}
	if len(input.Operations) == 0 {
		return fmt.Errorf("selecione ao menos uma operação")
	}

	seen := make(map[Operation]bool, len(input.Operations))
	for _, op := range input.Operations {
		if !op.Valid() {
			return fmt.Errorf("operação desconhecida %q", op)
		}
		if seen[op] {
			return fmt.Errorf("operação %q repetida", op)
		}
		seen[op] = true
	}

	if input.MileageKm < 0 || input.MileageKm > maxMileageKm {
		return fmt.Errorf("quilometragem deve estar entre 0 e %d km", maxMileageKm)
	}
	if input.CostCents != nil && (*input.CostCents < 0 || *input.CostCents > maxCostCents) {
		return fmt.Errorf("valor fora do limite")
	}
	if input.Notes != nil && len(*input.Notes) > maxNotesLength {
		return fmt.Errorf("observações devem ter até %d caracteres", maxNotesLength)
	}
	if input.MechanicName != nil && strings.TrimSpace(*input.MechanicName) == "" {
		return fmt.Errorf("nome do mecânico não pode ficar em branco")
	}

	if len(input.Parts) > maxParts {
		return fmt.Errorf("um registro aceita até %d peças", maxParts)
	}
	for i, part := range input.Parts {
		if strings.TrimSpace(part.Name) == "" {
			return fmt.Errorf("peça %d: nome é obrigatório", i+1)
		}
		if len(part.Name) > maxPartName {
			return fmt.Errorf("peça %d: nome muito longo", i+1)
		}
		if part.Quantity < 1 || part.Quantity > maxPartQty {
			return fmt.Errorf("peça %d: quantidade deve estar entre 1 e %d", i+1, maxPartQty)
		}
		if part.CostCents != nil && (*part.CostCents < 0 || *part.CostCents > maxCostCents) {
			return fmt.Errorf("peça %d: valor fora do limite", i+1)
		}
	}

	return nil
}
