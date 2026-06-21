import 'package:flutter_test/flutter_test.dart';
import 'package:quickvpn/vpn/management_parser.dart';
import 'package:quickvpn/vpn/vpn_models.dart';

void main() {
  group('parseManagementLine', () {
    test('maps >STATE: CONNECTING to a connecting stage event', () {
      final e = parseManagementLine('>STATE:1610000000,CONNECTING,,,,,,');
      expect(e, isA<StageEvent>());
      expect((e as StageEvent).stage, VpnStage.connecting);
    });

    test('maps >STATE: CONNECTED with extra fields', () {
      final e = parseManagementLine(
        '>STATE:1610000000,CONNECTED,SUCCESS,10.8.0.2,203.0.113.5,1194,,',
      );
      expect((e as StageEvent).stage, VpnStage.connected);
    });

    test('maps AUTH / GET_CONFIG / ASSIGN_IP / RECONNECTING / EXITING', () {
      VpnStage stageOf(String s) =>
          (parseManagementLine('>STATE:0,$s,,,,') as StageEvent).stage;
      expect(stageOf('AUTH'), VpnStage.authenticating);
      expect(stageOf('GET_CONFIG'), VpnStage.gettingConfig);
      expect(stageOf('ASSIGN_IP'), VpnStage.assigningIp);
      expect(stageOf('RECONNECTING'), VpnStage.reconnecting);
      expect(stageOf('EXITING'), VpnStage.exiting);
    });

    test('parses >BYTECOUNT: into in/out counters', () {
      final e = parseManagementLine('>BYTECOUNT:12345,67890');
      expect(e, isA<ByteCountEvent>());
      final b = e as ByteCountEvent;
      expect(b.bytesIn, 12345);
      expect(b.bytesOut, 67890);
    });

    test('detects a password prompt and its realm', () {
      final e = parseManagementLine(">PASSWORD:Need 'Auth' username/password");
      expect(e, isA<PasswordNeeded>());
      expect((e as PasswordNeeded).realm, 'Auth');
    });

    test('detects auth verification failure', () {
      final e = parseManagementLine(">PASSWORD:Verification Failed: 'Auth'");
      expect(e, isA<AuthFailed>());
    });

    test('detects hold waiting', () {
      final e = parseManagementLine('>HOLD:Waiting for hold release...');
      expect(e, isA<HoldWaiting>());
    });

    test('ignores command acks and unknown lines', () {
      expect(parseManagementLine('SUCCESS: real-time state set to ON'), isNull);
      expect(parseManagementLine('>STATE:0,SOMETHING_NEW,,,,'), isNull);
      expect(parseManagementLine(''), isNull);
    });
  });
}
