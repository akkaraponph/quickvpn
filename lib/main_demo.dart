// Screenshot / demo harness — NOT a shipped entrypoint (the real app is
// main.dart). It renders the actual QuickVpnApp UI with an in-memory store of
// demo profiles and a scripted fake controller, so the README screenshots of
// each usage state can be captured without a real VPN server or touching the
// user's real saved profiles.
//
// Pick the state with the QUICKVPN_DEMO_STATE env var:
//   vault       profiles imported, one selected, idle (default)
//   connecting  mid-handshake (busy orb, CONNECTING)
//   connected   tunnel up with live throughput
//
// Build once, then launch the same binary per state:
//   flutter build macos --release -t lib/main_demo.dart
//   QUICKVPN_DEMO_STATE=connected \
//     build/macos/Build/Products/Release/quickvpn.app/Contents/MacOS/quickvpn

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'main.dart';
import 'profile_store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'vpn/vpn_controller.dart';
import 'vpn/vpn_models.dart';

/// A minimal .ovpn body with a bare `auth-user-pass` so the profile shows the
/// credentials (🔑) affordance.
const _authConfig = '''
client
dev tun
proto udp
remote vpn.acme.example 1194
auth-user-pass
remote-cert-tls server
''';

const _noAuthConfig = '''
client
dev tun
proto udp
remote tokyo.public.example 1194
remote-cert-tls server
''';

/// In-memory store: seeds demo profiles and ignores writes, so the real
/// shared_preferences profiles are never read or overwritten.
class _DemoStore extends ProfileStore {
  final List<VpnProfile> _profiles;
  final int? _selected;
  _DemoStore(this._profiles, this._selected);

  @override
  Future<({List<VpnProfile> profiles, int? selectedIndex})> load() async =>
      (profiles: _profiles, selectedIndex: _selected);

  @override
  Future<void> save(List<VpnProfile> profiles, int? selectedIndex) async {}
}

/// A fake controller that simply replays one scripted [VpnStage] (plus stats
/// when connected) so each screenshot lands on a known state.
class _DemoController implements VpnController {
  final VpnStage _target;
  final VpnStats _stats;
  final _stage = StreamController<VpnStage>.broadcast();
  final _statsCtrl = StreamController<VpnStats>.broadcast();

  _DemoController(this._target, this._stats);

  @override
  Stream<VpnStage> get stage => _stage.stream;
  @override
  Stream<VpnStats> get stats => _statsCtrl.stream;
  @override
  VpnStage get currentStage => _target;

  @override
  Future<void> initialize() async {
    // Listeners are attached in initState before this runs; defer one microtask
    // so the first frame is built, then push the scripted state.
    scheduleMicrotask(() {
      if (_target != VpnStage.disconnected) _stage.add(_target);
      if (_target == VpnStage.connected) _statsCtrl.add(_stats);
    });
  }

  @override
  Future<VpnReadiness> checkReadiness() async => const VpnReadiness.ready();

  @override
  Future<void> connect(VpnConnectionRequest request) async {
    _stage.add(VpnStage.connected);
    _statsCtrl.add(_stats);
  }

  @override
  Future<void> disconnect() async => _stage.add(VpnStage.disconnected);

  @override
  void dispose() {
    _stage.close();
    _statsCtrl.close();
  }
}

({VpnStage stage, VpnStats stats}) _scriptFor(String state) {
  switch (state) {
    case 'connecting':
      return (stage: VpnStage.connecting, stats: VpnStats.zero);
    case 'connected':
      return (
        stage: VpnStage.connected,
        stats: const VpnStats(
          duration: Duration(hours: 0, minutes: 42, seconds: 17),
          bytesIn: 193004000,
          bytesOut: 24500000,
        ),
      );
    case 'vault':
    default:
      return (stage: VpnStage.disconnected, stats: VpnStats.zero);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final state = Platform.environment['QUICKVPN_DEMO_STATE'] ?? 'vault';
  final script = _scriptFor(state);

  final profiles = <VpnProfile>[
    VpnProfile(
      name: 'Acme Corp — Frankfurt',
      rawConfig: _authConfig,
      username: 'a.phikulsri',
      password: 'demo-password',
    ),
    VpnProfile(name: 'Home Lab — Raspberry Pi', rawConfig: _authConfig),
    VpnProfile(name: 'Tokyo — Public Node', rawConfig: _noAuthConfig),
  ];

  final theme = ThemeController(); // defaults to dark; never .load()ed here
  runApp(_DemoRoot(
    theme: theme,
    store: _DemoStore(profiles, 0),
    controller: _DemoController(script.stage, script.stats),
  ));
}

class _DemoRoot extends StatelessWidget {
  final ThemeController theme;
  final ProfileStore store;
  final VpnController controller;

  const _DemoRoot({
    required this.theme,
    required this.store,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: theme.mode,
        home: QuickVpnApp(
          controller: controller,
          themeController: theme,
          store: store,
        ),
      ),
    );
  }
}
