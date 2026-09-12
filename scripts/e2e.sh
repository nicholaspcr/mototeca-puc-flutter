#!/bin/sh
# End-to-end smoke test of the Mototeca API, run from inside the compose
# network so no request crosses the host boundary.
set -eu

API=http://api:8080
CNPJ=11222333000181
PLATE=ABC1D23

say() { printf '\n=== %s ===\n' "$1"; }

call() { # call <procedure> <json> [auth header]
  if [ $# -ge 3 ]; then
    curl -sS -X POST "$API/$1" -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $3" -d "$2"
  else
    curl -sS -X POST "$API/$1" -H 'Content-Type: application/json' -d "$2"
  fi
}

say "health"
curl -sS -o /dev/null -w 'healthz -> %{http_code}\n' "$API/healthz"

# Signing up and signing in are interchangeable here so the script can be run
# repeatedly against the same database.
token_of() { echo "$1" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }

say "create workshop (or sign in if it already exists)"
SIGNUP=$(call mototeca.workshop.v1.WorkshopService/CreateWorkshop \
  "{\"cnpj\":\"$CNPJ\",\"name\":\"Oficina do Zé\",\"password\":\"senha-forte-123\"}")
echo "$SIGNUP"
TOKEN=$(token_of "$SIGNUP")
if [ -z "$TOKEN" ]; then
  TOKEN=$(token_of "$(call mototeca.workshop.v1.WorkshopService/Login \
    "{\"cnpj\":\"$CNPJ\",\"password\":\"senha-forte-123\"}")")
fi
[ -n "$TOKEN" ] || { echo "FAIL: no workshop token"; exit 1; }

say "login with the same credentials"
call mototeca.workshop.v1.WorkshopService/Login \
  "{\"cnpj\":\"11.222.333/0001-81\",\"password\":\"senha-forte-123\"}" | head -c 200
echo

say "login with a wrong password (expect unauthenticated)"
call mototeca.workshop.v1.WorkshopService/Login \
  "{\"cnpj\":\"$CNPJ\",\"password\":\"errada-errada\"}"
echo

say "register the vehicle (already-exists is fine on a re-run)"
call mototeca.vehicle.v1.VehicleService/CreateVehicle \
  "{\"plate\":\"$PLATE\",\"chassi\":\"9C2KC1670GR000001\",\"make\":\"Honda\",\"model\":\"CG 160 Start\",\"year\":2022}"
echo

say "create a service record WITHOUT a token (expect unauthenticated)"
call mototeca.service.v1.ServiceRecordService/CreateServiceRecord \
  "{\"plate\":\"$PLATE\",\"operations\":[\"SERVICE_TYPE_OIL_CHANGE\"],\"mileageKm\":18420}"
echo

say "create a service record with two operations and parts"
RECORD=$(call mototeca.service.v1.ServiceRecordService/CreateServiceRecord \
  "{\"plate\":\"abc-1d23\",\"mechanicName\":\"José Carlos\",
    \"operations\":[\"SERVICE_TYPE_OIL_CHANGE\",\"SERVICE_TYPE_CHAIN_AND_SPROCKET\"],
    \"mileageKm\":18420,\"costCents\":24500,
    \"notes\":\"Óleo 10w30 trocado, corrente lubrificada.\",
    \"parts\":[{\"name\":\"Óleo 10w30\",\"quantity\":1,\"costCents\":6200},
               {\"name\":\"Kit relação\",\"quantity\":1,\"costCents\":14500}]}" "$TOKEN")
echo "$RECORD"
RECORD_ID=$(echo "$RECORD" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

say "public history lookup by plate (no token)"
call mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate \
  "{\"plate\":\"$PLATE\"}"
echo

say "workshop dashboard (token required)"
call mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords "{}" "$TOKEN"
echo

say "get one record by id (public)"
call mototeca.service.v1.ServiceRecordService/GetServiceRecord "{\"id\":\"$RECORD_ID\"}" | head -c 300
echo

say "reject an invalid record (no operations)"
call mototeca.service.v1.ServiceRecordService/CreateServiceRecord \
  "{\"plate\":\"$PLATE\",\"operations\":[],\"mileageKm\":100}" "$TOKEN"
echo

say "reject a tampered token"
call mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords "{}" "not.a.real.token"
echo

printf '\nE2E COMPLETE\n'

# --- Proprietário -------------------------------------------------------------

say "create owner (or sign in if already registered)"
OWNER=$(call mototeca.owner.v1.OwnerService/CreateOwner \
  '{"name":"Marcos Souza","phone":"(31) 99000-1234","password":"senha-forte-123"}')
echo "$OWNER"
OWNER_TOKEN=$(token_of "$OWNER")
if [ -z "$OWNER_TOKEN" ]; then
  OWNER_TOKEN=$(token_of "$(call mototeca.owner.v1.OwnerService/Login \
    '{"phone":"31990001234","password":"senha-forte-123"}')")
fi
[ -n "$OWNER_TOKEN" ] || { echo "FAIL: no owner token"; exit 1; }

say "owner login with wrong password (expect unauthenticated)"
call mototeca.owner.v1.OwnerService/Login \
  "{\"phone\":\"31990001234\",\"password\":\"errada\"}"
echo

say "owner token must NOT work on a workshop endpoint"
call mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords "{}" "$OWNER_TOKEN"
echo

say "workshop token must NOT work on an owner endpoint"
call mototeca.owner.v1.OwnerService/ListMyVehicles "{}" "$TOKEN"
echo

say "owner claims the bike"
call mototeca.owner.v1.OwnerService/ClaimVehicle "{\"plate\":\"$PLATE\"}" "$OWNER_TOKEN"
echo

say "minhas motos (reminder derived from the history)"
call mototeca.owner.v1.OwnerService/ListMyVehicles "{}" "$OWNER_TOKEN"
echo

printf '\nOWNER FLOW COMPLETE\n'
