// Basic smoke test for QuickVPN.
//
// The openvpn_flutter plugin talks to native code over a MethodChannel and an
// EventChannel. There is no native side under `flutter test`, so we mock both
// channels to keep the widget's engine init quiet and deterministic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickvpn/main.dart';

const _vpnControl = MethodChannel('id.laskarmedia.openvpn_flutter/vpncontrol');
const _vpnStage = EventChannel('id.laskarmedia.openvpn_flutter/vpnstage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(_vpnControl, (call) async => null);
    messenger.setMockStreamHandler(
      _vpnStage,
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_vpnControl, null);
    messenger.setMockStreamHandler(_vpnStage, null);
  });

  testWidgets('QuickVPN renders import action and empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickVpnApp()));
    await tester.pump();

    expect(find.text('⚡ QuickVPN'), findsOneWidget);
    expect(find.text('Import .ovpn'), findsOneWidget);
    expect(find.textContaining('No profiles added yet'), findsOneWidget);
  });
}
