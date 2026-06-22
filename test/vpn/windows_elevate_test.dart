import 'package:flutter_test/flutter_test.dart';
import 'package:quickvpn/vpn/windows_vpn_controller.dart';

void main() {
  group('psSingleQuote', () {
    test('wraps a plain value in single quotes', () {
      expect(psSingleQuote('openvpn'), "'openvpn'");
    });

    test('preserves spaces and backslashes verbatim', () {
      expect(
        psSingleQuote(r'C:\Program Files\OpenVPN\bin\openvpn.exe'),
        r"'C:\Program Files\OpenVPN\bin\openvpn.exe'",
      );
    });

    test('doubles embedded single quotes', () {
      expect(psSingleQuote("a'b"), "'a''b'");
    });
  });

  group('buildWindowsElevateCommand', () {
    test('elevates the exe and quotes every argument', () {
      final cmd = buildWindowsElevateCommand(
        exe: r'C:\Program Files\OpenVPN\bin\openvpn.exe',
        args: const ['--config', r'C:\Temp\a b\profile.ovpn', '--verb', '3'],
      );
      expect(
        cmd,
        "Start-Process -FilePath 'C:\\Program Files\\OpenVPN\\bin\\openvpn.exe' "
        "-ArgumentList @('--config','C:\\Temp\\a b\\profile.ovpn','--verb','3') "
        '-Verb RunAs -WindowStyle Hidden',
      );
    });

    test('omits -ArgumentList when there are no args', () {
      final cmd = buildWindowsElevateCommand(exe: 'openvpn.exe', args: const []);
      expect(cmd, isNot(contains('-ArgumentList')));
      expect(cmd, contains('-Verb RunAs'));
    });
  });
}
