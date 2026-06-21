import 'vpn_models.dart';

/// Events parsed from the OpenVPN management interface output stream.
/// See: https://github.com/OpenVPN/openvpn/blob/master/doc/management-notes.txt
sealed class ManagementEvent {
  const ManagementEvent();
}

class StageEvent extends ManagementEvent {
  final VpnStage stage;
  final String stateToken;
  const StageEvent(this.stage, this.stateToken);
}

class ByteCountEvent extends ManagementEvent {
  final int bytesIn;
  final int bytesOut;
  const ByteCountEvent(this.bytesIn, this.bytesOut);
}

class PasswordNeeded extends ManagementEvent {
  /// The auth realm, e.g. "Auth".
  final String realm;
  const PasswordNeeded(this.realm);
}

class AuthFailed extends ManagementEvent {
  final String message;
  const AuthFailed(this.message);
}

class HoldWaiting extends ManagementEvent {
  const HoldWaiting();
}

/// Map an OpenVPN `>STATE:` token to a neutral [VpnStage]. Returns null for
/// tokens we don't surface.
VpnStage? stageFromStateToken(String token) {
  switch (token) {
    case 'CONNECTING':
    case 'RESOLVE':
    case 'TCP_CONNECT':
    case 'WAIT':
      return VpnStage.connecting;
    case 'AUTH':
      return VpnStage.authenticating;
    case 'GET_CONFIG':
      return VpnStage.gettingConfig;
    case 'ASSIGN_IP':
    case 'ADD_ROUTES':
      return VpnStage.assigningIp;
    case 'CONNECTED':
      return VpnStage.connected;
    case 'RECONNECTING':
      return VpnStage.reconnecting;
    case 'EXITING':
      return VpnStage.exiting;
    default:
      return null;
  }
}

/// Parse a single management-interface line into a [ManagementEvent], or null
/// when the line carries nothing we act on (command acks, unknown states).
ManagementEvent? parseManagementLine(String rawLine) {
  final line = rawLine.trim();
  if (line.isEmpty) return null;

  if (line.startsWith('>STATE:')) {
    final fields = line.substring('>STATE:'.length).split(',');
    if (fields.length < 2) return null;
    final stage = stageFromStateToken(fields[1]);
    return stage == null ? null : StageEvent(stage, fields[1]);
  }

  if (line.startsWith('>BYTECOUNT:')) {
    final parts = line.substring('>BYTECOUNT:'.length).split(',');
    if (parts.length < 2) return null;
    final inB = int.tryParse(parts[0].trim());
    final outB = int.tryParse(parts[1].trim());
    if (inB == null || outB == null) return null;
    return ByteCountEvent(inB, outB);
  }

  if (line.startsWith('>PASSWORD:')) {
    final body = line.substring('>PASSWORD:'.length);
    if (body.startsWith('Verification Failed')) {
      return AuthFailed(body);
    }
    // e.g. Need 'Auth' username/password
    final realm = RegExp(r"Need '([^']+)'").firstMatch(body)?.group(1);
    if (realm != null) return PasswordNeeded(realm);
    return null;
  }

  if (line.startsWith('>HOLD:')) {
    return const HoldWaiting();
  }

  return null;
}
