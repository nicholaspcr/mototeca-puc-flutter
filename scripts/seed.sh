#!/bin/sh
# Fills an empty API with the same sample data as the in-app demo: two
# workshops, a bike with history from both, an owner with a bike due for an
# oil change, and a note a previous owner left on the demo bike.
#
# Usage: API=http://localhost:8080 sh scripts/seed.sh
# Runs once: when the demo plate already has history it does nothing.
set -eu

API=${API:-http://localhost:8080}
PASSWORD=senha-forte-123
PLATE=ABC1D23

rpc() { # <procedure> <json> [token]
  curl -sS -X POST "$API/mototeca.$1" -H 'Content-Type: application/json' \
    ${3:+-H "Authorization: Bearer $3"} -d "$2"
}
token() { sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }

if rpc service.v1.ServiceRecordService/ListServiceRecordsByPlate "{\"plate\":\"$PLATE\"}" |
  grep -q '"records"'; then
  echo "seed: $PLATE already has history, nothing to do"
  exit 0
fi

workshop() { # <cnpj> <name>
  rpc workshop.v1.WorkshopService/CreateWorkshop \
    "{\"cnpj\":\"$1\",\"name\":\"$2\",\"password\":\"$PASSWORD\"}" >/dev/null
  rpc workshop.v1.WorkshopService/Login "{\"cnpj\":\"$1\",\"password\":\"$PASSWORD\"}" | token
}
owner() { # <phone> <name>
  rpc owner.v1.OwnerService/CreateOwner \
    "{\"name\":\"$2\",\"phone\":\"$1\",\"password\":\"$PASSWORD\"}" >/dev/null
  rpc owner.v1.OwnerService/Login "{\"phone\":\"$1\",\"password\":\"$PASSWORD\"}" | token
}
vehicle() { # <token> <plate> <chassi> <make> <model> <year>
  rpc vehicle.v1.VehicleService/CreateVehicle \
    "{\"plate\":\"$2\",\"chassi\":\"$3\",\"make\":\"$4\",\"model\":\"$5\",\"year\":$6}" "$1" >/dev/null
}
record() { # <token> <json>
  rpc service.v1.ServiceRecordService/CreateServiceRecord "$2" "$1" | grep -q '"record"' ||
    { echo "seed: record refused: $2" >&2; exit 1; }
}
days_ago() { date -v-"$1"d +%F 2>/dev/null || date -d "$1 days ago" +%F; }

ZE=$(workshop 11222333000181 'Oficina do Zé')
CENTER=$(workshop 11444555000149 'Moto Center BH')
[ -n "$ZE" ] && [ -n "$CENTER" ] || { echo "seed: workshop sign-in failed" >&2; exit 1; }

vehicle "$ZE" "$PLATE" 9C2KC1670GR000001 Honda 'CG 160 Start' 2022
vehicle "$ZE" KLM3C45 9C6KG0710M0000002 Yamaha 'Factor 150' 2021

# A previous owner kept a note on the demo bike, then sold it.
ANA=$(owner 31990005678 'Ana Lima')
rpc owner.v1.OwnerService/ClaimVehicle "{\"plate\":\"$PLATE\",\"chassiSuffix\":\"000001\"}" "$ANA" >/dev/null
rpc owner.v1.OwnerService/AddMaintenanceNote "{\"plate\":\"$PLATE\",
  \"clientId\":\"0b6e3c1a-5d2f-4e7a-9c8b-1a2b3c4d5e6f\",\"doneOn\":\"$(days_ago 150)\",
  \"description\":\"Troca de óleo feita em casa, óleo 10w30.\",\"mileageKm\":14100,\"costCents\":5200}" "$ANA" >/dev/null
rpc owner.v1.OwnerService/ReleaseVehicle "{\"plate\":\"$PLATE\"}" "$ANA" >/dev/null

record "$CENTER" "{\"plate\":\"$PLATE\",\"mechanicName\":\"Paulo Nunes\",
  \"operations\":[\"SERVICE_TYPE_SCHEDULED_REVIEW\",\"SERVICE_TYPE_BRAKES\"],
  \"mileageKm\":12400,\"costCents\":31000,
  \"notes\":\"Revisão dos 12.000 km e pastilhas dianteiras trocadas.\",
  \"parts\":[{\"name\":\"Pastilha de freio\",\"quantity\":2,\"costCents\":9800}]}"
record "$ZE" "{\"plate\":\"$PLATE\",\"mechanicName\":\"José Carlos\",
  \"operations\":[\"SERVICE_TYPE_OIL_CHANGE\",\"SERVICE_TYPE_CHAIN_AND_SPROCKET\"],
  \"mileageKm\":16150,\"costCents\":24500,
  \"notes\":\"Óleo 10w30 trocado, corrente lubrificada e ajustada.\",
  \"parts\":[{\"name\":\"Óleo 10w30\",\"quantity\":1,\"costCents\":6200},
             {\"name\":\"Kit relação\",\"quantity\":1,\"costCents\":14500}]}"
record "$ZE" "{\"plate\":\"$PLATE\",\"mechanicName\":\"José Carlos\",
  \"operations\":[\"SERVICE_TYPE_TIRES\"],\"mileageKm\":18420,\"costCents\":48000,
  \"notes\":\"Pneu traseiro substituído; dianteiro com 60% de vida.\",
  \"parts\":[{\"name\":\"Pneu traseiro 90/90-18\",\"quantity\":1,\"costCents\":38000}]}"

# The demo owner's own bike, due for an oil change, so Lembretes has content.
MARCOS=$(owner 31990001234 'Marcos Souza')
rpc owner.v1.OwnerService/ClaimVehicle '{"plate":"KLM3C45","chassiSuffix":"000002"}' "$MARCOS" >/dev/null
record "$ZE" '{"plate":"KLM3C45","mechanicName":"José Carlos",
  "operations":["SERVICE_TYPE_OIL_CHANGE"],"mileageKm":21300,"costCents":18000}'
record "$CENTER" '{"plate":"KLM3C45","mechanicName":"Paulo Nunes",
  "operations":["SERVICE_TYPE_ELECTRICAL"],"mileageKm":23900,"costCents":22000,
  "notes":"Bateria substituída."}'

echo "seed: done. Oficina 11222333000181, dono 31990001234, senha $PASSWORD"
