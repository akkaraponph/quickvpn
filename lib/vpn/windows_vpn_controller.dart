import 'dart:io';

import 'base_cli_vpn_controller.dart';
import 'openvpn_locator.dart';
import 'vpn_controller.dart';

/// Windows engine: same management-interface driver as macOS/Linux, but gains
/// admin rights through UAC by relaunching `openvpn.exe` elevated via
/// PowerShell's `Start-Process -Verb RunAs`. The elevated process runs
/// detached (no `--daemon` on Windows); we still control and stop it entirely
/// over the loopback management socket.
class WindowsVpnController extends CliVpnController {
  @override
  String? locateBinary() =>
      locateOpenVpnOnSystem(candidates: defaultWindowsOpenVpnPaths);

  @override
  VpnReadiness whenBinaryMissing() => const VpnReadiness.notReady(
        'OpenVPN is not installed',
        remediation:
            'Install the OpenVPN community client from openvpn.net/community-downloads',
      );

  // Start-Process detaches the elevated process for us; no daemon flags.
  @override
  List<String> daemonizeArgs(String pidPath) => const [];

  // NTFS inherits per-user permissions on the temp dir; nothing to tighten.
  @override
  Future<void> secureConfig(File configFile) async {}

  @override
  Future<void> launchElevated(
    String openvpn,
    List<String> args,
    Directory workDir,
  ) async {
    final command = buildWindowsElevateCommand(exe: openvpn, args: args);
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', command],
    );
    if (r.exitCode != 0) {
      final err = '${r.stdout}\n${r.stderr}';
      if (_looksLikeUacDecline(err)) {
        throw const PrivilegeRequestCancelled();
      }
      throw Exception('Failed to start OpenVPN (elevation): ${err.trim()}');
    }
  }

  bool _looksLikeUacDecline(String err) {
    final e = err.toLowerCase();
    // UAC decline surfaces as Win32 error 1223 ("operation was canceled").
    return e.contains('canceled') ||
        e.contains('cancelled') ||
        e.contains('1223');
  }
}

/// Quote a single argument for a PowerShell single-quoted string literal:
/// wrap in `'…'` and double any embedded single quotes. Single-quoting stops
/// PowerShell from interpreting `$`, spaces, backslashes, etc.
String psSingleQuote(String s) => "'${s.replaceAll("'", "''")}'";

/// Build the PowerShell one-liner that relaunches [exe] elevated (UAC) with
/// [args], hidden and detached. Pure so the quoting can be unit-tested.
String buildWindowsElevateCommand({
  required String exe,
  required List<String> args,
}) {
  final base = 'Start-Process -FilePath ${psSingleQuote(exe)}';
  final tail = ' -Verb RunAs -WindowStyle Hidden';
  if (args.isEmpty) return '$base$tail';
  final argList = args.map(psSingleQuote).join(',');
  return '$base -ArgumentList @($argList)$tail';
}
