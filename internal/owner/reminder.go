package owner

import "fmt"

// OilChangeIntervalKm is an estimate. A real product would read it from the
// model's manual rather than assume one figure for every bike.
const OilChangeIntervalKm = 3000

// dueSoonKm — roughly a month of city riding.
const dueSoonKm = 600

// Reminder is where a bike stands against its next oil change.
type Reminder struct {
	Text  string
	IsDue bool
	// 0 when no oil change was ever recorded.
	DueAtKm int
}

func (v OwnedVehicle) Reminder() Reminder {
	if v.LastOilChangeKm == nil {
		if v.ServiceCount == 0 {
			return Reminder{Text: "Sem serviços registrados", IsDue: false}
		}
		return Reminder{Text: "Sem troca de óleo registrada", IsDue: true}
	}

	dueAt := *v.LastOilChangeKm + OilChangeIntervalKm
	remaining := dueAt - v.CurrentMileageKm

	switch {
	case remaining <= 0:
		return Reminder{
			Text:    fmt.Sprintf("Troca de óleo atrasada em %d km", -remaining),
			IsDue:   true,
			DueAtKm: dueAt,
		}
	case remaining <= dueSoonKm:
		return Reminder{
			Text:    fmt.Sprintf("Troca de óleo em %d km", remaining),
			IsDue:   true,
			DueAtKm: dueAt,
		}
	default:
		return Reminder{
			Text:    fmt.Sprintf("Em dia · próxima troca em %d km", remaining),
			IsDue:   false,
			DueAtKm: dueAt,
		}
	}
}
