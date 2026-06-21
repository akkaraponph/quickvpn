# QuickVPN — macOS OpenVPN engine (launcher + management interface)

**Date:** 2026-06-21
**Status:** Approved (design)
**Author:** Akkarapon Phikulsri (with Claude)

## Problem

`openvpn_flutter` ships only Android and iOS implementations. On macOS its
platform channels have no native handler, so `connect`/`initialize` throw
`MissingPluginException` and no tunnel can ever be established. QuickVPN must
actually connect on macOS.

The "correct" Apple path (a Network Extension `PacketTunnelProvider`) is
hard-gated on a paid Apple Developer Program membership, which is unavailable.
We therefore use the **launcher** path: drive the open-source `openvpn` CLI and
control/monitor it through OpenVPN's **management interface** — the same
mechanism Tunnelblick and OpenVPN-GUI use.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Path | Launcher: Flutter app drives the `openvpn` CLI |
| Implementation | **Pure Dart** via `dart:io` (no Swift plugin needed) |
| Privilege | **Support both**: default macOS admin dialog (`osascript`) per connect, plus an in-app "Make connections seamless" action that installs a scoped `sudoers` rule |
| `openvpn` binary | Use Homebrew's; detect path, prompt `brew install openvpn` if missing |
| Scope | Basics only: connect, disconnect, live status stages, throughput |

## Architecture — platform-split controller

The widget talks to an abstract `VpnController`; the concrete type is chosen at
runtime. Android/iOS behavior is unchanged.

```
lib/vpn/vpn_models.dart            // VpnStage enum, VpnStats (neutral, no openvpn_flutter types)
lib/vpn/vpn_controller.dart        // abstract: connect/disconnect + stage & stats streams + isReady
lib/vpn/management_parser.dart     // PURE functions: parse >STATE: / >BYTECOUNT: lines -> models
lib/vpn/openvpn_locator.dart       // find the openvpn binary (injectable lookup for tests)
lib/vpn/mac_vpn_controller.dart    // macOS: osascript/sudo + openvpn + management socket
lib/vpn/mobile_vpn_controller.dart // Android/iOS: wraps openvpn_flutter, maps to neutral models
lib/vpn/vpn_controller_factory.dart// returns the right controller for the platform
lib/vpn/privilege_helper.dart      // detect/install the sudoers rule (macOS)
```

### Neutral models

```dart
enum VpnStage {
  disconnected, connecting, authenticating, gettingConfig,
  assigningIp, connected, reconnecting, exiting, error,
}

class VpnStats {
  final Duration duration;
  final int bytesIn;   // cumulative bytes
  final int bytesOut;
}
```

## macOS connect flow (data flow)

1. **Locate `openvpn`** — check `/opt/homebrew/sbin/openvpn`,
   `/usr/local/sbin/openvpn`, then `which openvpn`. If missing → typed
   `OpenVpnNotInstalled` → UI shows *"Run: `brew install openvpn`"*.
2. **Write temp config** — `profile.rawConfig` → `$TMPDIR/quickvpn/<name>.ovpn`,
   perms `0600`. Password is **not** written to disk (see Security).
3. **Launch privileged + daemonized** with a local management interface on a
   free loopback port:
   ```
   openvpn --config <tmp> --management 127.0.0.1 <port> \
           --management-hold --management-query-passwords \
           --auth-nocache --daemon --writepid <pid> --log <log> --verb 3
   ```
   - Seamless mode: `sudo -n openvpn …`
   - Dialog mode: `osascript -e 'do shell script "openvpn …" with administrator privileges'`
4. **Drive via management socket** — Dart `Socket` → `127.0.0.1:<port>` (retry
   ~3s for the daemon to bind). Send `state on`, `bytecount 1`, answer the
   `>PASSWORD:` prompt with the profile's username/password, then `hold release`.
5. **Stream to UI** — parse `>STATE:` → `VpnStage`; `>BYTECOUNT:` → `VpnStats`.
6. **Disconnect** — send `signal SIGTERM` over the socket → openvpn exits →
   delete temp files. No root needed for disconnect.

## Privilege model — "support both"

- Default: `osascript` admin dialog each connect (zero setup).
- "Make connections seamless" → installs `/etc/sudoers.d/quickvpn`:
  ```
  <user> ALL=(root) NOPASSWD: /opt/homebrew/sbin/openvpn
  ```
  Scoped to the exact detected binary, NOPASSWD for that binary only, validated
  with `visudo -c` before install; install itself uses one admin dialog. The app
  detects the rule via `sudo -n openvpn --version` and switches to seamless
  automatically.

## Required project change — disable the macOS sandbox

A sandboxed app cannot spawn `osascript`/`openvpn` or write temp configs. Remove
`com.apple.security.app-sandbox` from both macOS entitlement files (keep
`network.client`). Consequence: distribution is outside the Mac App Store —
acceptable for this tool.

## Error handling

- Admin dialog cancelled (`osascript` exit -128) → treat as cancelled → back to
  Disconnected with a snackbar.
- Auth failure (`>PASSWORD:Verification Failed`) → "Authentication failed".
- Management socket connect timeout → error + best-effort cleanup (SIGTERM via
  pid if reachable).
- `openvpn` missing → `OpenVpnNotInstalled` → install guidance.
- `sudoers` install failure / `visudo -c` rejects → do not install, surface error.

## Security (safety-first)

- Password passed only over the loopback management socket; never written to disk.
- Temp config `0600` in a private dir; deleted on disconnect.
- Management bound to `127.0.0.1` only.
- `sudoers` rule never broadened beyond the single `openvpn` binary path.

## Testing

- **Unit (no root):** `management_parser` (`>STATE:`, `>BYTECOUNT:` → models);
  `openvpn_locator` discovery with injected lookup; factory platform selection.
- **Widget:** existing smoke test, updated to mock `VpnController`.
- **Manual:** documented checklist to connect to `vpn.snru.ac.th` using
  `vpnprofile/test.ovpn` + SNRU credentials (needs real root + live server;
  cannot be automated).

## Out of scope (YAGNI for v1)

Auto-reconnect, on-demand rules, launch-at-login, bundling the `openvpn` binary,
Windows/Linux engines.
```
