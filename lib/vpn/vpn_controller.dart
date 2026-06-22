import 'vpn_models.dart';

/// What the UI needs from a VPN profile to connect. Kept tiny and independent
/// of the widget-layer model so controllers don't reach back into the UI.
class VpnConnectionRequest {
  final String name;
  final String config; // raw .ovpn contents
  final String? username;
  final String? password;

  /// Whether the config embeds a client cert (used by the mobile engine's
  /// `certIsRequired`; the macOS engine reads the cert from the config itself).
  final bool certIsRequired;

  const VpnConnectionRequest({
    required this.name,
    required this.config,
    this.username,
    this.password,
    this.certIsRequired = false,
  });
}

/// Abstract engine the UI talks to. Concrete implementations:
///   - MobileVpnController (Android/iOS, wraps openvpn_flutter)
///   - MacVpnController / LinuxVpnController / WindowsVpnController
///     (desktop, drive the openvpn CLI in pure Dart — see CliVpnController)
abstract class VpnController {
  /// Connection-stage updates.
  Stream<VpnStage> get stage;

  /// Live throughput / duration updates.
  Stream<VpnStats> get stats;

  /// Latest known stage (synchronous convenience for the UI).
  VpnStage get currentStage;

  /// One-time setup. Safe to call on every platform.
  Future<void> initialize();

  /// Whether the engine can actually connect on this machine right now
  /// (e.g. the openvpn binary is installed). Throws nothing — returns a reason
  /// when not ready.
  Future<VpnReadiness> checkReadiness();

  Future<void> connect(VpnConnectionRequest request);

  Future<void> disconnect();

  void dispose();
}

/// Result of [VpnController.checkReadiness].
class VpnReadiness {
  final bool isReady;

  /// Null when ready; otherwise a short, user-facing reason.
  final String? reason;

  /// Optional remediation hint (e.g. a command to run).
  final String? remediation;

  const VpnReadiness.ready()
      : isReady = true,
        reason = null,
        remediation = null;

  const VpnReadiness.notReady(this.reason, {this.remediation}) : isReady = false;
}

/// Thrown when a connect is attempted but the openvpn binary is missing.
class OpenVpnNotInstalled implements Exception {
  final String message;
  const OpenVpnNotInstalled([
    this.message = "openvpn is not installed. Install it with: brew install openvpn",
  ]);
  @override
  String toString() => message;
}

/// Thrown when the user cancels the macOS administrator-password dialog.
class PrivilegeRequestCancelled implements Exception {
  const PrivilegeRequestCancelled();
  @override
  String toString() => "Administrator permission was cancelled.";
}
