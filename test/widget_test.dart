// Smoke test for QuickVPN. Injects a fake VpnController so the widget never
// touches a real engine (no platform channels, no spawned processes).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickvpn/main.dart';
import 'package:quickvpn/vpn/vpn_controller.dart';
import 'package:quickvpn/vpn/vpn_models.dart';

class FakeVpnController implements VpnController {
  final _stage = StreamController<VpnStage>.broadcast();
  final _stats = StreamController<VpnStats>.broadcast();

  @override
  Stream<VpnStage> get stage => _stage.stream;
  @override
  Stream<VpnStats> get stats => _stats.stream;
  @override
  VpnStage get currentStage => VpnStage.disconnected;
  @override
  Future<void> initialize() async {}
  @override
  Future<VpnReadiness> checkReadiness() async => const VpnReadiness.ready();
  @override
  Future<void> connect(VpnConnectionRequest request) async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {
    _stage.close();
    _stats.close();
  }
}

void main() {
  testWidgets('QuickVPN renders import action and empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QuickVpnApp(controller: FakeVpnController())),
    );
    // flutter_svg loads the logo asset asynchronously; let it settle so no
    // loader Timer outlives the test.
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Quick'), findsOneWidget);
    expect(find.text('Import .ovpn'), findsOneWidget);
    expect(find.textContaining('No profiles added yet'), findsOneWidget);
    expect(find.textContaining('DISCONNECTED'), findsOneWidget);
  });
}
