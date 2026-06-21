import 'dart:async';
import 'dart:io';

import 'mac_vpn_controller.dart';
import 'mobile_vpn_controller.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';

/// Returns the VPN engine appropriate for the current platform.
VpnController createVpnController() {
  if (Platform.isMacOS) return MacVpnController();
  if (Platform.isAndroid || Platform.isIOS) return MobileVpnController();
  return UnsupportedVpnController();
}

/// Fallback for platforms QuickVPN doesn't yet have an engine for
/// (Windows / Linux). The UI still runs; connecting reports "not supported".
class UnsupportedVpnController implements VpnController {
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  final _statsCtrl = StreamController<VpnStats>.broadcast();

  @override
  Stream<VpnStage> get stage => _stageCtrl.stream;

  @override
  Stream<VpnStats> get stats => _statsCtrl.stream;

  @override
  VpnStage get currentStage => VpnStage.disconnected;

  @override
  Future<void> initialize() async {}

  @override
  Future<VpnReadiness> checkReadiness() async => const VpnReadiness.notReady(
        'VPN connection is not supported on this platform yet',
      );

  @override
  Future<void> connect(VpnConnectionRequest request) async {
    throw UnsupportedError('VPN connection is not supported on this platform.');
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    _stageCtrl.close();
    _statsCtrl.close();
  }
}
