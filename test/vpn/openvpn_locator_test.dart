import 'package:flutter_test/flutter_test.dart';
import 'package:quickvpn/vpn/openvpn_locator.dart';

void main() {
  group('locateOpenVpn', () {
    test('returns the first candidate that exists', () {
      final path = locateOpenVpn(
        candidates: ['/a/openvpn', '/b/openvpn'],
        exists: (p) => p == '/a/openvpn',
      );
      expect(path, '/a/openvpn');
    });

    test('skips missing candidates and returns a later one', () {
      final path = locateOpenVpn(
        candidates: ['/a/openvpn', '/b/openvpn'],
        exists: (p) => p == '/b/openvpn',
      );
      expect(path, '/b/openvpn');
    });

    test('falls back to which when no candidate exists', () {
      final path = locateOpenVpn(
        candidates: ['/a/openvpn'],
        exists: (_) => false,
        which: () => '/usr/bin/openvpn',
      );
      expect(path, '/usr/bin/openvpn');
    });

    test('returns null when nothing is found', () {
      final path = locateOpenVpn(
        candidates: ['/a/openvpn'],
        exists: (_) => false,
        which: () => null,
      );
      expect(path, isNull);
    });

    test('ships the known Homebrew sbin paths as defaults', () {
      expect(defaultOpenVpnPaths, contains('/opt/homebrew/sbin/openvpn'));
      expect(defaultOpenVpnPaths, contains('/usr/local/sbin/openvpn'));
    });

    test('ships Linux package locations', () {
      expect(defaultLinuxOpenVpnPaths, contains('/usr/sbin/openvpn'));
      expect(defaultLinuxOpenVpnPaths, contains('/usr/bin/openvpn'));
    });

    test('ships the Windows installer locations (with .exe)', () {
      expect(defaultWindowsOpenVpnPaths,
          contains(r'C:\Program Files\OpenVPN\bin\openvpn.exe'));
      expect(
          defaultWindowsOpenVpnPaths.every((p) => p.endsWith('.exe')), isTrue);
    });
  });
}
