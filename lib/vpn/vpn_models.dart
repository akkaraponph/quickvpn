// Platform-neutral VPN models shared by every VpnController implementation,
// so the UI never depends on openvpn_flutter or any engine-specific type.

/// Connection lifecycle stages, mapped from each engine's native stage values
/// (openvpn_flutter on mobile, the OpenVPN management interface on macOS).
enum VpnStage {
  disconnected,
  connecting,
  authenticating,
  gettingConfig,
  assigningIp,
  connected,
  reconnecting,
  exiting,
  error,
}

extension VpnStageLabel on VpnStage {
  /// Human-readable label for the status line.
  String get label {
    switch (this) {
      case VpnStage.disconnected:
        return "Disconnected";
      case VpnStage.connecting:
        return "Connecting";
      case VpnStage.authenticating:
        return "Authenticating";
      case VpnStage.gettingConfig:
        return "Getting config";
      case VpnStage.assigningIp:
        return "Assigning IP";
      case VpnStage.connected:
        return "Connected";
      case VpnStage.reconnecting:
        return "Reconnecting";
      case VpnStage.exiting:
        return "Disconnecting";
      case VpnStage.error:
        return "Error";
    }
  }

  bool get isConnected => this == VpnStage.connected;
}

/// Live tunnel statistics. Cumulative byte counters plus elapsed duration.
class VpnStats {
  final Duration duration;
  final int bytesIn;
  final int bytesOut;

  const VpnStats({
    this.duration = Duration.zero,
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  static const VpnStats zero = VpnStats();
}
