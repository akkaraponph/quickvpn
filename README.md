# ⚡ QuickVPN

A sleek, fast OpenVPN client built with Flutter. Import your `.ovpn` profiles,
see them in a clean list, and connect with a single tap.

> _QuickVPN by [refactorroom.com](https://refactorroom.com)_

---

## What it does

- **Import** `.ovpn` profiles from disk.
- **List** all imported profiles in a tidy "profile vault".
- **Connect / disconnect** with one tap on a big power toggle.
- **Credentials** — profiles using `auth-user-pass` get a 🔑 to store a
  username/password; you're auto-prompted on first connect.
- **Live metrics** — connection duration and throughput (▼ in / ▲ out) while
  connected.
- **Selection safeguard** — you can't switch the active profile mid-session.

## Platform support

| Platform | Tunnel | How |
|----------|:------:|-----|
| **Android** | ✅ | [`openvpn_flutter`](https://pub.dev/packages/openvpn_flutter) (bundled native OpenVPN engine) |
| **iOS** | ✅ | `openvpn_flutter` (requires a Network Extension target + paid Apple Developer account) |
| **macOS** | ✅ | Pure-Dart launcher that drives the Homebrew `openvpn` binary via its management interface — **no Apple Developer account, no Network Extension** |
| **Windows / Linux** | ⛔ | UI runs; connecting reports "not supported yet" |

### Why macOS is special

`openvpn_flutter` ships **only** Android and iOS implementations. Apple's
"correct" path (a Network Extension `PacketTunnelProvider`) is gated behind a
paid Apple Developer Program membership. So on macOS QuickVPN takes the
**launcher** approach — the same mechanism Tunnelblick and OpenVPN-GUI use:

1. It spawns the real, battle-tested `openvpn` CLI (it does **not** reimplement
   the OpenVPN protocol).
2. It controls and monitors that process over OpenVPN's **management interface**
   — a local loopback socket — for status, throughput, credentials, and a clean
   disconnect.
3. Creating the tunnel device needs root, so `openvpn` is launched either via
   the native macOS administrator dialog (default) or, optionally, a tightly
   scoped passwordless `sudoers` rule for seamless connects.

## Getting started

### Prerequisites
- Flutter 3.44+ (Dart SDK `^3.12.2`)
- **macOS only:** [Homebrew](https://brew.sh) + the openvpn binary:
  ```sh
  brew install openvpn
  ```
  (QuickVPN looks for it at `/opt/homebrew/sbin/openvpn` or `/usr/local/sbin/openvpn`
  and shows an install banner if it's missing.)

### Run
```sh
flutter pub get

# macOS
flutter run -d macos

# Android (emulator or device)
flutter run -d <android-device>
```

> **macOS note:** the app sandbox is intentionally disabled (a sandboxed app
> cannot spawn `openvpn`/`osascript`), so distribution is outside the Mac App
> Store. Changing entitlements requires a **full rebuild**, not a hot restart.

### Connecting (macOS)
1. **Import .ovpn** → pick your profile.
2. Tap the 🔑 on the profile and enter your username/password (for
   `auth-user-pass` profiles).
3. Select the profile and tap the power button.
4. Authenticate in the macOS admin dialog → status walks
   `CONNECTING → AUTHENTICATING → … → CONNECTED`.
5. _Optional:_ tap ⚡ **"Make connections seamless"** to install a `sudoers`
   rule (scoped to only the `openvpn` binary, validated with `visudo`) so future
   connects need no password.

## Project structure

```
lib/
  main.dart                       UI (profile vault, toggle, credentials, metrics)
  vpn/
    vpn_models.dart               Neutral VpnStage / VpnStats
    vpn_controller.dart           Abstract engine interface + request/readiness types
    vpn_controller_factory.dart   Picks the engine per platform
    management_parser.dart        Pure parser for the OpenVPN management protocol
    openvpn_locator.dart          Homebrew openvpn binary discovery
    privilege_helper.dart         macOS privilege model (admin dialog / sudoers)
    mac_vpn_controller.dart       macOS engine (launcher + management socket)
    mobile_vpn_controller.dart    Android/iOS engine (wraps openvpn_flutter)
test/
  vpn/management_parser_test.dart
  vpn/openvpn_locator_test.dart
  widget_test.dart                Smoke test with an injected fake controller
docs/superpowers/specs/           Design spec for the macOS engine
```

The UI talks only to the abstract `VpnController`; each platform's engine
implements it. This keeps mobile behavior untouched while macOS gets its own
pure-Dart implementation.

## Testing

```sh
flutter analyze
flutter test
```

Pure logic (the management-protocol parser and binary discovery) is unit-tested.
The live macOS tunnel requires root, the admin dialog, and a real server, so it's
validated manually.

## Security notes

- Passwords are sent only over the loopback management socket — **never written
  to disk**.
- Temp config files are created `0600` in a private directory and deleted on
  disconnect.
- The optional `sudoers` rule is scoped to the **single** `openvpn` binary path,
  `NOPASSWD` for that binary only, and validated with `visudo -c` before install.
- The management interface binds to `127.0.0.1` only.

## License

[MIT](LICENSE) © 2026 Akkarapon Phikulsri (refactorroom.com)
