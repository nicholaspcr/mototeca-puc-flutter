#!/bin/sh
# Runs the API on this Mac and installs both apps on a USB-connected iPhone,
# pointed at it. macOS only: needs Xcode (signed in to an Apple ID), Flutter
# and Docker.
#
# Usage, from mototeca/:  sh scripts/iphone.sh [both|rider|shop]
#   RESET=1   start from an empty database (drops the compose volumes)
#   HOST=ip   address the phone uses to reach this Mac (auto-detected)
#   TEAM=id   Apple team id, when Xcode knows more than one
#   DEVICE=id iPhone id from `flutter devices`, when more than one is plugged in
#
# The cable installs the apps. Their traffic needs a network path to the Mac:
# the same Wi-Fi, or the iPhone's Personal Hotspot shared over the cable.
set -eu
cd "$(dirname "$0")/.."

APPS=${1:-both}
case $APPS in both) APPS='rider shop' ;; rider | shop) ;; *) sed -n 2,13p "$0"; exit 2 ;; esac

for tool in flutter xcodebuild docker curl; do
  command -v $tool >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

# Personal Hotspot over USB gives the Mac a 172.20.10.x address; prefer it.
detect_host() {
  for i in $(ifconfig -l); do
    ip=$(ipconfig getifaddr "$i" 2>/dev/null) || continue
    case $ip in 172.20.10.*) echo "$ip"; return ;; esac
  done
  ipconfig getifaddr en0 || ipconfig getifaddr en1 || true
}
HOST=${HOST:-$(detect_host)}
[ -n "$HOST" ] || { echo "no network address: join Wi-Fi or turn on Personal Hotspot" >&2; exit 1; }
API=http://$HOST:8080

echo "== backend on $API"
if [ "${RESET:-}" = 1 ]; then docker compose down -v; fi
# Photo URLs are built from this, so the phone must be able to reach it too.
STORAGE_PUBLIC_URL=http://$HOST:9000 docker compose up -d --build
curl -sf --retry 60 --retry-connrefused --retry-delay 1 "$API/healthz" >/dev/null
API=$API sh scripts/seed.sh

DEVICE=${DEVICE:-$(flutter devices | awk -F' • ' '$3 == "ios" && !/simulator/ {print $2; exit}')}
[ -n "$DEVICE" ] || { echo "no iPhone found: plug it in, unlock it and trust this Mac" >&2; exit 1; }

cd mobile
for app in $APPS; do
  if [ "$app" = rider ]; then id=motociclista name='Mototeca Motociclista'
  else id=oficina name='Mototeca Oficina'; fi
  echo "== installing $name on $DEVICE"
  {
    echo "MOTOTECA_APP_ID = $id"
    echo "MOTOTECA_APP_NAME = $name"
    if [ -n "${TEAM:-}" ]; then echo "DEVELOPMENT_TEAM = $TEAM"; fi
  } >ios/Flutter/App.xcconfig
  flutter run --release --no-resident -d "$DEVICE" -t "lib/main_$app.dart" \
    --dart-define=MOTOTECA_API_URL="$API"
done

cat <<EOF

Done. Both apps talk to $API.
First install only: if iOS says "Untrusted Developer", open Settings >
General > VPN & Device Management, trust your Apple ID, then run again.
Tap "Allow" when an app asks to find devices on the local network.
EOF
