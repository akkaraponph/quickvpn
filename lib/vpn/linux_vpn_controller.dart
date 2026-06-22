import 'dart:io';

import 'base_cli_vpn_controller.dart';
import 'openvpn_locator.dart';
import 'vpn_controller.dart';

/// Linux engine: same management-interface driver as macOS, but gains root via
/// PolicyKit (`pkexec`, which shows a graphical auth dialog) — or, if the user
/// has configured passwordless sudo for openvpn, seamlessly via `sudo -n`.
class LinuxVpnController extends CliVpnController {
  @override
  String? locateBinary() =>
      locateOpenVpnOnSystem(candidates: defaultLinuxOpenVpnPaths);

  @override
  VpnReadiness whenBinaryMissing() => const VpnReadiness.notReady(
        'openvpn is not installed',
        remediation:
            'Install it, e.g.:  sudo apt install openvpn   (or dnf / pacman)',
      );

  @override
  List<String> daemonizeArgs(String pidPath) =>
      ['--daemon', '--writepid', pidPath];

  @override
  Future<void> secureConfig(File configFile) => chmod600(configFile);

  @override
  Future<void> launchElevated(
    String openvpn,
    List<String> args,
    Directory workDir,
  ) async {
    // Fast path: passwordless sudo already configured for this binary.
    if (await _hasPasswordlessSudo(openvpn)) {
      final r = await Process.run('sudo', ['-n', openvpn, ...args]);
      if (r.exitCode != 0) {
        throw Exception('Failed to start openvpn (sudo): ${r.stderr}');
      }
      return;
    }

    // Preferred: pkexec shows a graphical PolicyKit authentication dialog.
    if (_hasPkexec()) {
      final r = await Process.run('pkexec', [openvpn, ...args]);
      // pkexec: 126 = dismissed / not authorized, 127 = auth could not be obtained.
      if (r.exitCode == 126 || r.exitCode == 127) {
        throw const PrivilegeRequestCancelled();
      }
      if (r.exitCode != 0) {
        throw Exception('Failed to start openvpn (pkexec): ${r.stderr}');
      }
      return;
    }

    // Last resort: plain sudo (needs a terminal or a cached credential).
    final r = await Process.run('sudo', [openvpn, ...args]);
    if (r.exitCode != 0) {
      throw Exception(
        'Could not gain root to start openvpn. Install pkexec (policykit) or '
        'configure passwordless sudo for openvpn. Details: ${r.stderr}',
      );
    }
  }

  bool _hasPkexec() => _onPath('pkexec');

  bool _onPath(String binary) {
    try {
      return Process.runSync('which', [binary]).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasPasswordlessSudo(String openvpn) async {
    try {
      final r = await Process.run('sudo', ['-n', openvpn, '--version']);
      return '${r.stdout}'.contains('OpenVPN');
    } catch (_) {
      return false;
    }
  }
}
