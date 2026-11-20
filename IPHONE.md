# Running Mototeca on an iPhone

Both apps (Mototeca Oficina and Mototeca Motociclista) are built on a Mac and
installed on an iPhone over the cable. The API runs on the same Mac, and the
apps on the phone call it over the local network.

## 1. Prepare the Mac (once)

1. Install Xcode from the App Store, open it once, and accept the license:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -runFirstLaunch
   ```

2. In Xcode → Settings → Accounts, add your Apple ID. A free account is
   enough, but apps signed with it stop opening after 7 days. Run the script
   again to renew them.
3. Install Flutter (https://docs.flutter.dev/get-started/install/macos).
   `flutter doctor` must show a check next to Xcode.
4. Install and start Docker (Docker Desktop or OrbStack).
5. Get the code:

   ```bash
   git clone https://github.com/nicholaspcr/mototeca-puc-flutter.git mototeca
   cd mototeca
   ```

   Later runs only need `git pull`.

## 2. Prepare the iPhone (once)

1. Connect it with the cable, unlock it, and tap **Trust** on the "Trust This
   Computer?" prompt.
2. Turn on Developer Mode in Settings → Privacy & Security → Developer
   Mode. The phone restarts.

## 3. Connect the phone to the Mac's network

The cable installs the apps but does not carry their traffic. Use one of these:

- **Same Wi-Fi.** Connect the iPhone and the Mac to the same Wi-Fi network.
- **Personal Hotspot over the cable.** Turn on Personal Hotspot on the iPhone
  with the cable plugged in. The Mac gets a `172.20.10.x` address, and the
  script prefers it.

## 4. Install

From the `mototeca/` folder:

```bash
RESET=1 sh scripts/iphone.sh
```

The script:

1. finds the Mac's address on the network;
2. starts PostgreSQL, the photo storage and the API with `docker compose`;
3. fills the database with sample data (`scripts/seed.sh`);
4. builds both apps in release mode and installs them on the iPhone, pointed
   at the API on the Mac.

`RESET=1` empties the database first. Drop it to keep the current data.

## 5. First launch

- **"Untrusted Developer".** Go to Settings → General → VPN & Device
  Management, tap your Apple ID, tap **Trust**, then run the script again.
- **Local network prompt.** Tap **Allow** when each app asks to find devices
  on the local network. Without it, the apps cannot reach the API.

## Sample data

| | |
|---|---|
| Workshop | CNPJ `11222333000181`, password `senha-forte-123` |
| Owner | phone `31990001234`, password `senha-forte-123` |
| Bike with no owner | plate `ABC1D23`, chassi ending `000001` |
| Owner's bike | plate `KLM3C45` |

## Options

| Command | Effect |
|---|---|
| `sh scripts/iphone.sh rider` | installs only Mototeca Motociclista |
| `sh scripts/iphone.sh shop` | installs only Mototeca Oficina |
| `HOST=192.168.0.10 sh scripts/iphone.sh` | uses this address for the Mac instead of detecting it |
| `TEAM=ABCDE12345 sh scripts/iphone.sh` | signs with this Apple team, when Xcode knows several |
| `DEVICE=<id> sh scripts/iphone.sh` | picks this phone from `flutter devices` |

## Troubleshooting

| Problem | Fix |
|---|---|
| "no iPhone found" | Unlock the phone, check the cable, and run `flutter devices`. |
| Signing error or "no development team" | Open `mobile/ios/Runner.xcworkspace` in Xcode, select Runner → Signing & Capabilities, pick your team, then run the script again. |
| The app says it cannot reach the server | In Safari on the iPhone, open `http://<mac-address>:8080/healthz`. A blank page means the API is reachable. An error means the network path is blocked. |
| Safari cannot open `/healthz` either | Check that both devices are on the same network. Allow incoming connections for Docker in the macOS firewall. If a VPN such as Mullvad is on, enable its local network sharing or disconnect it. |
| The Mac's address changed (new Wi-Fi) | Run the script again. The apps are rebuilt with the new address. |
| Photos do not load | The photo links use the address from the last run. Run the script again with `RESET=1`. |
