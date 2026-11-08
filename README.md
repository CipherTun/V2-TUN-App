<div align="center">

<img src="docs/banner.svg" alt="V2-TUN" width="100%">

<br>

![platform](https://img.shields.io/badge/platform-Android-34a853?style=for-the-badge&labelColor=0b1220)
![flutter](https://img.shields.io/badge/Flutter-3.35%2B-4285f4?style=for-the-badge&labelColor=0b1220)
![kotlin](https://img.shields.io/badge/Kotlin-VpnService-a78bfa?style=for-the-badge&labelColor=0b1220)
![package](https://img.shields.io/badge/package-io.surprise.vpn-fbbc05?style=for-the-badge&labelColor=0b1220)

**[Features](#-features)** • **[Quick start](#-quick-start)** • **[Architecture](#-architecture)** • **[Settings](#-settings)** • **[Notes](#-notes-and-limits)**

</div>

## What it is

V2-TUN is an Android app built around the [V2-TUN](https://github.com/CipherTun/V2-TUN) tunnel library, an Xray-free tunnel written in Go. The library is compiled with `gomobile` into an AAR (Java package `io.surprise.mobile`), a Kotlin `VpnService` hands it the TUN device, and a Flutter interface drives everything.

The look is greyish blue and black. The default accent is an animated ring in the four Google colors. Fonts are bundled, so Android's system font setting cannot replace them.

## ✨ Features

| Area | What you get |
| --- | --- |
| **Dashboard** | Animated connect orb, live speed, session time, today and all-time usage |
| **Configs** | Import share links or JSON from the clipboard, subscription URLs with auto-update, search, sort by latency, duplicate, select the fastest |
| **Logs** | App event log with level filters, copy and clear |
| **Tools** | Speed test, host scanner, payload lab, route explainer, live routing rules, route lists, backup and restore |
| **Tunneling** | TUN (system-wide) or local SOCKS5 with optional auth, MTU, DNS, fake-IP DNS, traffic sniffing |
| **Routing** | Default action, domain strategy, bypass LAN, block QUIC, block BitTorrent, split tunneling by domain and IP |
| **Per-app VPN** | Allow list or deny list of apps |
| **Reliability** | Other configs as failover backups, latency sort, WebSocket keepalive, idle timeout, reconnect on drop, connection check after connecting |
| **Android** | Quick Settings tile, foreground notification with live speeds, shortcut to the system Always-on VPN page |
| **Appearance** | 7 accent presets and a custom color picker, reduced motion, haptics |

Protocols come from the library: VLESS, VMess, Trojan, Shadowsocks, SSH, SOCKS4/5, HTTP(S) proxies, Hysteria 1 and 2, with REALITY, XTLS Vision, WebSocket, HTTPUpgrade, HTTP/2, gRPC and XHTTP transports. See the library README for details.

## 🚀 Quick start

You need Flutter, Git, and for the library build: Go, `gomobile`, and the Android SDK with the NDK.

```bash
git clone https://github.com/CipherTun/V2-TUN-App.git
cd V2-TUN-App
./setup.sh ../v2tun_flutter        # creates the Flutter project, builds the AAR, links everything
cd ../v2tun_flutter && flutter run
```

`setup.sh` runs `flutter create --org io.surprise --project-name vpn`, so the applicationId and namespace are `io.surprise.vpn`, then copies this repository's sources into the fresh project. By default it builds the library from `CipherTun/V2-TUN`; override with `V2TUN_REPO` and `V2TUN_BRANCH`. To use a prebuilt AAR, put it next to the script as `v2tun.aar`.

## 🧱 Architecture

```text
lib/
  core/     models, persistence (shared_preferences), state (ChangeNotifier), platform channel
  ui/       Dashboard, Configs, Logs, Tools, Settings, theme
android_src/
  kotlin/   MainActivity, V2TunVpnService, V2TunTileService, Hub (events)
  AndroidManifest.xml
assets/fonts/   Newsreader, DM Sans, JetBrains Mono (bundled)
```

- Dart talks to Kotlin over one `MethodChannel` and one `EventChannel` (`io.surprise.vpn/core`, `io.surprise.vpn/events`).
- Library calls that can block (ping, speed test, scan) run off the main thread.
- The service resolves the server name before the VPN exists, protects the tunnel's own sockets, routes `::/0` into the interface so IPv6 is dropped instead of leaking, and gives the TUN descriptor to `StartTunEx`.
- The only runtime dependency besides Flutter is `shared_preferences`.

## ⚙️ Settings

Open the settings icon at the top left of the Dashboard. Groups: Appearance, Tunneling, Routing, Per-app VPN, Reliability, App behavior. Settings are merged into the selected config as its `routing`, `backups`, `directDns`, `ws.pingSec` and related fields before connecting.

## ⚠️ Notes and limits

- The library is IPv4 only inside the tunnel.
- A kill switch cannot be enabled by an app. Use Android's Always-on VPN and "Block connections without VPN" in system settings; the app links to that page.
- The Logs tab shows the app's own events. The library has no log stream.
- The connection check dials through the whole config chain. It shows the config works, not that every app's traffic is flowing.
- Hysteria, XTLS Vision and certificate verify-name are described by the library as tested against loopback only. Try them against your own server.

## 🛠️ Development

```bash
flutter analyze
flutter test
```

Issues and pull requests are welcome.

## License

No license has been chosen yet. Add a `LICENSE` file before accepting outside contributions.
