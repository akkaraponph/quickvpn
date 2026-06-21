import 'dart:async';

import 'package:openvpn_flutter/openvpn_flutter.dart';

import 'management_parser.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';

/// Android / iOS engine: wraps openvpn_flutter and maps its native stage /
/// status values onto QuickVPN's neutral models.
class MobileVpnController implements VpnController {
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  final _statsCtrl = StreamController<VpnStats>.broadcast();
  late final OpenVPN _engine;
  VpnStage _stage = VpnStage.disconnected;

  MobileVpnController() {
    _engine = OpenVPN(
      onVpnStageChanged: (_, rawStage) => _emitStage(_mapRawStage(rawStage)),
      onVpnStatusChanged: (status) {
        if (status == null) return;
        _statsCtrl.add(VpnStats(
          duration: _parseHms(status.duration),
          bytesIn: int.tryParse(status.byteIn ?? '0') ?? 0,
          bytesOut: int.tryParse(status.byteOut ?? '0') ?? 0,
        ));
      },
    );
  }

  @override
  Stream<VpnStage> get stage => _stageCtrl.stream;

  @override
  Stream<VpnStats> get stats => _statsCtrl.stream;

  @override
  VpnStage get currentStage => _stage;

  @override
  Future<void> initialize() async {
    await _engine.initialize(
      groupIdentifier: 'group.com.refactorroom.quickvpn',
      providerBundleIdentifier: 'com.refactorroom.quickvpn.NetworkExtension',
      localizedDescription: 'QuickVPN Engine',
    );
  }

  @override
  Future<VpnReadiness> checkReadiness() async => const VpnReadiness.ready();

  @override
  Future<void> connect(VpnConnectionRequest request) async {
    await _engine.connect(
      request.config,
      request.name,
      username: request.username,
      password: request.password,
      certIsRequired: request.certIsRequired,
    );
  }

  @override
  Future<void> disconnect() async => _engine.disconnect();

  @override
  void dispose() {
    _stageCtrl.close();
    _statsCtrl.close();
  }

  void _emitStage(VpnStage stage) {
    _stage = stage;
    if (!_stageCtrl.isClosed) _stageCtrl.add(stage);
  }

  /// openvpn_flutter emits native stage strings; reuse the management-token map
  /// where it overlaps and cover the mobile-only ones explicitly.
  VpnStage _mapRawStage(String raw) {
    final token = raw.trim().toUpperCase().replaceAll(' ', '_');
    final mapped = stageFromStateToken(token);
    if (mapped != null) return mapped;
    switch (token) {
      case 'AUTHENTICATING':
        return VpnStage.authenticating;
      case 'PREPARE':
      case 'VPN_GENERATE_CONFIG':
      case 'UDP_CONNECT':
        return VpnStage.connecting;
      case 'DISCONNECTING':
        return VpnStage.exiting;
      case 'DENIED':
      case 'ERROR':
        return VpnStage.error;
      case 'DISCONNECTED':
      case 'NONETWORK':
      case 'NO_CONNECTION':
      case 'NOCONNECTION':
        return VpnStage.disconnected;
      default:
        return VpnStage.disconnected;
    }
  }

  Duration _parseHms(String? s) {
    if (s == null) return Duration.zero;
    final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration.zero;
  }
}
