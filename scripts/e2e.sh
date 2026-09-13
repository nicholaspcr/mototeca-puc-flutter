#!/bin/sh
# End-to-end check of every Mototeca endpoint, run from inside the compose
# network so no request crosses the host boundary. Each step asserts the
# response code, so a regression fails the run instead of scrolling past.
#
# The data is fixed and every write tolerates a previous run, so it doubles as
# the demo seed (mobile/DEMO.md). The last step drains the owner login rate
# limit: wait about 30 seconds before running it again.
set -u

API=${API:-http://api:8080}
STORAGE=${STORAGE:-http://storage:9000}

CNPJ=11222333000181       # Oficina do Zé, the demo workshop
OTHER_CNPJ=11444555000149 # a second shop, for cross-workshop refusals
PHONE=31990001234
OTHER_PHONE=31990005678
PASSWORD=senha-forte-123
PLATE=ABC1D23

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0
BODY=''
CODE=''

section() { printf '\n== %s\n' "$1"; }

# Connect reports failures as {"code": "..."}; success is "ok".
read_response() {
  status=$(tail -n1 "$TMP/response")
  BODY=$(sed '$d' "$TMP/response")
  if [ "$status" = 200 ]; then
    CODE=ok
  else
    CODE=$(printf '%s' "$BODY" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
    CODE=${CODE:-http_$status}
  fi
}

# rpc <procedure> <json> [token]
rpc() {
  set -- "$1" "$2" "${3:-}"
  if [ -n "$3" ]; then
    curl -sS -w '\n%{http_code}' -X POST "$API/$1" -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $3" -d "$2" >"$TMP/response"
  else
    curl -sS -w '\n%{http_code}' -X POST "$API/$1" -H 'Content-Type: application/json' \
      -d "$2" >"$TMP/response"
  fi
  read_response
}

# upload <record id> <token> <curl args...>
upload() {
  url="$API/v1/service-records/$1/attachments" token=$2
  shift 2
  if [ -n "$token" ]; then
    curl -sS -w '\n%{http_code}' -X POST "$url" -H "Authorization: Bearer $token" "$@" >"$TMP/response"
  else
    curl -sS -w '\n%{http_code}' -X POST "$url" "$@" >"$TMP/response"
  fi
  read_response
}

pass() { passed=$((passed + 1)); printf 'ok    %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$(printf '%s' "$BODY" | head -c 300)"; }

# expect "<codes>" <label>: the last response's code is one of codes.
expect() {
  case " $1 " in
    *" $CODE "*) pass "$2 [$CODE]" ;;
    *) fail "$2: want $1, got $CODE" ;;
  esac
}

contains() { case "$BODY" in *"$1"*) pass "$2" ;; *) fail "$2: body lacks $1" ;; esac; }
lacks() { case "$BODY" in *"$1"*) fail "$2: body has $1" ;; *) pass "$2" ;; esac; }

field() { printf '%s' "$BODY" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
first_record() { printf '%s' "$BODY" | sed -n 's/.*"records":\[{"id":"\([^"]*\)".*/\1/p'; }

# Signs in, or signs up when the account does not exist yet.
workshop_session() { # <cnpj> <name>
  rpc mototeca.workshop.v1.WorkshopService/Login "{\"cnpj\":\"$1\",\"password\":\"$PASSWORD\"}"
  if [ "$CODE" != ok ]; then
    rpc mototeca.workshop.v1.WorkshopService/CreateWorkshop \
      "{\"cnpj\":\"$1\",\"name\":\"$2\",\"password\":\"$PASSWORD\"}"
  fi
  field token
}

owner_session() { # <phone> <name>
  rpc mototeca.owner.v1.OwnerService/Login "{\"phone\":\"$1\",\"password\":\"$PASSWORD\"}"
  if [ "$CODE" != ok ]; then
    rpc mototeca.owner.v1.OwnerService/CreateOwner \
      "{\"name\":\"$2\",\"phone\":\"$1\",\"password\":\"$PASSWORD\"}"
  fi
  field token
}

# ---------------------------------------------------------------------------
section "health and CORS"

curl -sS -o /dev/null -w '%{http_code}' "$API/healthz" >"$TMP/status"
BODY='' CODE=$(cat "$TMP/status")
expect 200 "healthz"

preflight() {
  curl -sS -i -X OPTIONS "$API/mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate" \
    -H "Origin: $1" -H 'Access-Control-Request-Method: POST' \
    -H 'Access-Control-Request-Headers: content-type,authorization' | tr -d '\r'
}
BODY=$(preflight http://localhost:53211)
contains "Access-Control-Allow-Origin: http://localhost:53211" "preflight from the Flutter dev server is allowed"
BODY=$(preflight https://evil.example)
lacks "Access-Control-Allow-Origin" "preflight from a foreign origin is refused"

# ---------------------------------------------------------------------------
section "workshop accounts"

TOKEN=$(workshop_session "11.222.333/0001-81" "Oficina do Zé")
[ -n "$TOKEN" ] && pass "workshop signs in or up with a punctuated CNPJ" || fail "no workshop token"
OTHER_TOKEN=$(workshop_session "$OTHER_CNPJ" "Oficina Concorrente")
[ -n "$OTHER_TOKEN" ] && pass "second workshop signs in or up" || fail "no second workshop token"

rpc mototeca.workshop.v1.WorkshopService/Login "{\"cnpj\":\"$CNPJ\",\"password\":\"errada-errada\"}"
expect unauthenticated "wrong password"
contains "CNPJ ou senha inválidos" "wrong password message does not reveal whether the CNPJ exists"

rpc mototeca.workshop.v1.WorkshopService/CreateWorkshop \
  "{\"cnpj\":\"$CNPJ\",\"name\":\"Duplicada\",\"password\":\"$PASSWORD\"}"
expect already_exists "registering a taken CNPJ"

# ---------------------------------------------------------------------------
section "vehicles"

VEHICLE="{\"plate\":\"$PLATE\",\"chassi\":\"9C2KC1670GR000001\",\"make\":\"Honda\",\"model\":\"CG 160 Start\",\"year\":2022}"

rpc mototeca.vehicle.v1.VehicleService/CreateVehicle "$VEHICLE"
expect unauthenticated "registering a vehicle anonymously"
rpc mototeca.vehicle.v1.VehicleService/CreateVehicle "$VEHICLE" "$TOKEN"
expect "ok already_exists" "workshop registers the demo bike"
rpc mototeca.vehicle.v1.VehicleService/CreateVehicle "$VEHICLE" "$TOKEN"
expect already_exists "registering the same plate twice"
rpc mototeca.vehicle.v1.VehicleService/CreateVehicle \
  '{"plate":"XYZ","chassi":"9C2KC1670GR000001","make":"Honda","model":"CG","year":2022}' "$TOKEN"
expect invalid_argument "malformed plate"

rpc mototeca.vehicle.v1.VehicleService/GetVehicleByPlate "{\"plate\":\"$PLATE\"}"
expect unauthenticated "chassi lookup without a session"
rpc mototeca.vehicle.v1.VehicleService/GetVehicleByPlate '{"plate":"abc-1d23"}' "$TOKEN"
expect ok "workshop looks the bike up with a messy plate"
contains '"chassi":"9C2KC1670GR000001"' "lookup returns the chassi to the workshop"
rpc mototeca.vehicle.v1.VehicleService/GetVehicleByPlate '{"plate":"ZZZ0Z00"}' "$TOKEN"
expect not_found "unregistered plate"

# ---------------------------------------------------------------------------
section "service records"

RECORD_JSON="{\"plate\":\"abc 1d23\",\"mechanicName\":\"José Carlos\",
  \"operations\":[\"SERVICE_TYPE_OIL_CHANGE\",\"SERVICE_TYPE_CHAIN_AND_SPROCKET\"],
  \"mileageKm\":18420,\"costCents\":24500,
  \"notes\":\"Óleo 10w30 trocado, corrente lubrificada.\",
  \"parts\":[{\"name\":\"Óleo 10w30\",\"quantity\":1,\"costCents\":6200},
             {\"name\":\"Kit relação\",\"quantity\":1,\"costCents\":14500}]}"

rpc mototeca.service.v1.ServiceRecordService/CreateServiceRecord "$RECORD_JSON"
expect unauthenticated "creating a record without a session"
rpc mototeca.service.v1.ServiceRecordService/CreateServiceRecord "$RECORD_JSON" "$TOKEN"
expect ok "workshop creates a record with two operations and parts"
RECORD_ID=$(printf '%s' "$BODY" | sed -n 's/.*"record":{"id":"\([^"]*\)".*/\1/p')

rpc mototeca.service.v1.ServiceRecordService/CreateServiceRecord \
  "{\"plate\":\"$PLATE\",\"operations\":[],\"mileageKm\":100}" "$TOKEN"
expect invalid_argument "record without operations"
contains "selecione ao menos uma operação" "validation message is in Portuguese"
rpc mototeca.service.v1.ServiceRecordService/CreateServiceRecord \
  '{"plate":"ZZZ0Z00","operations":["SERVICE_TYPE_TIRES"],"mileageKm":100}' "$TOKEN"
expect not_found "record for an unregistered plate"

rpc mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate "{\"plate\":\"$PLATE\"}"
expect ok "public history lookup without a session"
lacks "chassi" "public history does not expose the chassi"

rpc mototeca.service.v1.ServiceRecordService/GetServiceRecord "{\"id\":\"$RECORD_ID\"}"
expect ok "public record detail"
rpc mototeca.service.v1.ServiceRecordService/GetServiceRecord '{"id":"not-a-uuid"}'
expect not_found "malformed record id"

rpc mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords '{"limit":5}' "$TOKEN"
expect ok "workshop dashboard"
contains "\"countThisMonth\"" "dashboard carries the month count"
rpc mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords '{}' "not.a.real.token"
expect unauthenticated "tampered token"

# ---------------------------------------------------------------------------
section "photo uploads"

# A 1x1 PNG, so the script needs no fixture file on disk.
printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\2\0\0\0\220wS\336\0\0\0\014IDATx\234c\370\17\4\0\11\373\3\375\343\125\362\261\0\0\0\0IEND\256B`\202' >"$TMP/px.png"
printf '<html><script>alert(1)</script></html>' >"$TMP/page.html"

upload "$RECORD_ID" "$TOKEN" -F "file=@$TMP/px.png;type=image/png" -F phase=before
expect ok "workshop uploads a before photo"
PHOTO_URL=$(field url)

upload "$RECORD_ID" "" -F "file=@$TMP/px.png;type=image/png"
expect unauthenticated "upload without a session"
upload "$RECORD_ID" "$OTHER_TOKEN" -F "file=@$TMP/px.png;type=image/png"
expect not_found "upload onto another workshop's record"
upload "$RECORD_ID" "$TOKEN" -F "file=@$TMP/page.html;type=image/png"
expect invalid_argument "HTML disguised as a PNG"
upload "$RECORD_ID" "$TOKEN" -H 'Content-Type: application/json' -d '{}'
expect invalid_argument "upload that is not multipart"
upload not-a-uuid "$TOKEN" -F "file=@$TMP/px.png;type=image/png"
expect not_found "upload onto a malformed record id"
upload "$RECORD_ID" "$TOKEN" -F "file=@$TMP/px.png;type=image/png" -F kind=invoice -F phase=before
expect invalid_argument "invoice with a before/after phase"

# The API hands out URLs on the public host; inside the network that is storage.
OBJECT_PATH=${PHOTO_URL#http*://*/}
curl -sS -o "$TMP/downloaded" -w '%{http_code} %{content_type}' "$STORAGE/$OBJECT_PATH" >"$TMP/status"
BODY='' CODE=$(cat "$TMP/status")
expect "200 image/png" "stored photo is served back as image/png"

rpc mototeca.service.v1.ServiceRecordService/GetServiceRecord "{\"id\":\"$RECORD_ID\"}"
contains "PHOTO_PHASE_BEFORE" "record detail lists the photo"

# ---------------------------------------------------------------------------
section "corrections"

REVISION="{\"recordId\":\"$RECORD_ID\",\"operations\":[\"SERVICE_TYPE_TIRES\"],\"mileageKm\":18999,\"notes\":\"Correção: era pneu, não óleo.\"}"

rpc mototeca.service.v1.ServiceRecordService/ReviseServiceRecord "$REVISION"
expect unauthenticated "revising without a session"
rpc mototeca.service.v1.ServiceRecordService/ReviseServiceRecord "$REVISION" "$OTHER_TOKEN"
expect not_found "revising another workshop's record"
rpc mototeca.service.v1.ServiceRecordService/ReviseServiceRecord "$REVISION" "$TOKEN"
expect ok "workshop corrects its record"
contains "\"revisesRecordId\":\"$RECORD_ID\"" "correction points at the original"
contains "PHOTO_PHASE_BEFORE" "correction keeps the original's photo"
REVISED_ID=$(printf '%s' "$BODY" | sed -n 's/.*"record":{"id":"\([^"]*\)".*/\1/p')

rpc mototeca.service.v1.ServiceRecordService/ReviseServiceRecord "$REVISION" "$TOKEN"
expect failed_precondition "correcting the same record twice"

rpc mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate "{\"plate\":\"$PLATE\",\"limit\":1}"
[ "$(first_record)" = "$REVISED_ID" ] && pass "history shows the correction, not the original" ||
  fail "history's newest record is $(first_record), want $REVISED_ID"

# ---------------------------------------------------------------------------
section "owner accounts"

OWNER_TOKEN=$(owner_session "(31) 99000-1234" "Marcos Souza")
[ -n "$OWNER_TOKEN" ] && pass "owner signs in or up" || fail "no owner token"
OTHER_OWNER_TOKEN=$(owner_session "$OTHER_PHONE" "Ana Lima")
[ -n "$OTHER_OWNER_TOKEN" ] && pass "second owner signs in or up" || fail "no second owner token"

rpc mototeca.owner.v1.OwnerService/Login "{\"phone\":\"$PHONE\",\"password\":\"errada-errada\"}"
expect unauthenticated "owner wrong password"
rpc mototeca.owner.v1.OwnerService/CreateOwner \
  "{\"name\":\"Duplicado\",\"phone\":\"$PHONE\",\"password\":\"$PASSWORD\"}"
expect already_exists "registering a taken phone"

rpc mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords '{}' "$OWNER_TOKEN"
expect unauthenticated "owner token on a workshop endpoint"
rpc mototeca.owner.v1.OwnerService/ListMyVehicles '{}' "$TOKEN"
expect unauthenticated "workshop token on an owner endpoint"

rpc mototeca.vehicle.v1.VehicleService/CreateVehicle "$VEHICLE" "$OWNER_TOKEN"
expect already_exists "owner registering a bike a workshop already registered"

rpc mototeca.owner.v1.OwnerService/ClaimVehicle "{\"plate\":\"$PLATE\"}" "$OWNER_TOKEN"
expect ok "owner claims the bike"
rpc mototeca.owner.v1.OwnerService/ClaimVehicle "{\"plate\":\"$PLATE\"}" "$OWNER_TOKEN"
expect ok "claiming again is idempotent"
rpc mototeca.owner.v1.OwnerService/ClaimVehicle "{\"plate\":\"$PLATE\"}" "$OTHER_OWNER_TOKEN"
expect failed_precondition "a second owner cannot take the bike"
rpc mototeca.owner.v1.OwnerService/ClaimVehicle '{"plate":"ZZZ0Z00"}' "$OWNER_TOKEN"
expect not_found "claiming an unregistered plate"

rpc mototeca.owner.v1.OwnerService/ListMyVehicles '{}' "$OWNER_TOKEN"
expect ok "minhas motos"
contains "\"plate\":\"$PLATE\"" "the claimed bike is listed"
contains "\"reminder\"" "the bike carries a reminder"

rpc mototeca.owner.v1.OwnerService/ReleaseVehicle "{\"plate\":\"$PLATE\"}" "$OTHER_OWNER_TOKEN"
expect not_found "releasing a bike you do not hold"
rpc mototeca.owner.v1.OwnerService/ReleaseVehicle "{\"plate\":\"$PLATE\"}" "$OWNER_TOKEN"
expect ok "owner releases the bike"
rpc mototeca.owner.v1.OwnerService/ListMyVehicles '{}' "$OWNER_TOKEN"
lacks "\"plate\":\"$PLATE\"" "a released bike is no longer listed"

# ---------------------------------------------------------------------------
section "abuse limits"

head -c 1200000 /dev/zero | tr '\0' a | sed 's/^/{"plate":"/; s/$/"}/' >"$TMP/huge.json"
curl -sS -w '\n%{http_code}' -X POST "$API/mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate" \
  -H 'Content-Type: application/json' --data-binary "@$TMP/huge.json" >"$TMP/response"
read_response
expect resource_exhausted "RPC body over 1 MiB"

limited=''
for attempt in 1 2 3 4 5 6 7 8; do
  rpc mototeca.owner.v1.OwnerService/Login "{\"phone\":\"$PHONE\",\"password\":\"errada-errada\"}"
  if [ "$CODE" = resource_exhausted ]; then
    limited=$attempt
    break
  fi
done
[ -n "$limited" ] && pass "owner login is throttled (attempt $limited)" || fail "owner login never throttled"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
