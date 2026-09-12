package owner

import "fmt"

// OilChangeIntervalKm is how far the app assumes a bike goes between oil
// changes. A real product would vary this by model and by what the manual
// says; one constant is enough to make the reminder useful and is honest
// about being an estimate.
const OilChangeIntervalKm = 3000

// dueSoonKm is how close to the interval counts as "coming up" rather than
// "fine" — roughly a month of city riding.
const dueSoonKm = 600

// Reminder describes where a bike stands against its next oil change,
// derived entirely from the service history.
type Reminder struct {
	Text  string
	IsDue bool
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
			Text:  fmt.Sprintf("Troca de óleo atrasada em %d km", -remaining),
			IsDue: true,
		}
	case remaining <= dueSoonKm:
		return Reminder{
			Text:  fmt.Sprintf("Troca de óleo em %d km", remaining),
			IsDue: true,
		}
	default:
		return Reminder{
			Text:  fmt.Sprintf("Em dia · próxima troca em %d km", remaining),
			IsDue: false,
		}
	}
}
