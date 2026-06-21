import 'dart:io';

/// Manages how QuickVPN obtains root to launch the openvpn binary on macOS.
///
/// "Support both": by default each connect uses the native macOS administrator
/// dialog (via osascript). The user can opt into a one-time, tightly-scoped
/// sudoers rule that makes subsequent connects seamless (no dialog).
class PrivilegeHelper {
  static const sudoersFile = '/etc/sudoers.d/quickvpn';

  /// The exact sudoers line we install — NOPASSWD limited to the one binary.
  static String sudoersRule(String user, String openvpnPath) =>
      '$user ALL=(root) NOPASSWD: $openvpnPath';

  /// Current login name, for the sudoers rule.
  static String get currentUser =>
      Platform.environment['USER'] ?? Platform.environment['LOGNAME'] ?? '';

  /// Single-quote a string for safe use inside a /bin/sh command.
  static String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

  /// True when passwordless sudo for [openvpnPath] is already configured —
  /// detected by actually running `sudo -n <openvpn> --version` and seeing
  /// OpenVPN's banner (openvpn exits non-zero for --version, so we check stdout).
  static Future<bool> hasSeamlessSudo(String openvpnPath) async {
    try {
      final r = await Process.run('sudo', ['-n', openvpnPath, '--version']);
      final out = '${r.stdout}';
      return out.contains('OpenVPN');
    } catch (_) {
      return false;
    }
  }

  /// Install the scoped sudoers rule. Validates with `visudo -c` before placing
  /// the file, and uses ONE administrator dialog. Returns true on success.
  /// Throws [PrivilegeInstallCancelled] if the user dismisses the dialog.
  static Future<bool> installSeamlessSudo(String openvpnPath) async {
    final user = currentUser;
    if (user.isEmpty) return false;

    final rule = sudoersRule(user, openvpnPath);
    final tmp = await Directory.systemTemp.createTemp('quickvpn_sudoers');
    final stagePath = '${tmp.path}/quickvpn';
    await File(stagePath).writeAsString('$rule\n');

    // Validate, then install atomically as root. Validation failure aborts
    // before touching /etc/sudoers.d so we can never corrupt sudo.
    final script = [
      'set -e',
      'visudo -cf ${shQuote(stagePath)}',
      'install -m 0440 -o root -g wheel ${shQuote(stagePath)} ${shQuote(sudoersFile)}',
    ].join('\n');

    try {
      await _runPrivilegedScript(script);
      return await hasSeamlessSudo(openvpnPath);
    } finally {
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
  }

  /// Remove the seamless sudoers rule (also needs one administrator dialog).
  static Future<void> removeSeamlessSudo() async {
    await _runPrivilegedScript('rm -f ${shQuote(sudoersFile)}');
  }

  /// Run a /bin/sh script as root via the macOS administrator dialog.
  static Future<void> _runPrivilegedScript(String scriptBody) async {
    final tmp = await Directory.systemTemp.createTemp('quickvpn_priv');
    final scriptPath = '${tmp.path}/run.sh';
    await File(scriptPath).writeAsString('#!/bin/sh\n$scriptBody\n');
    try {
      final apple =
          'do shell script "/bin/sh ${shQuote(scriptPath)}" with administrator privileges';
      final r = await Process.run('osascript', ['-e', apple]);
      if (r.exitCode != 0) {
        final err = '${r.stderr}';
        if (err.contains('-128') || err.contains('User canceled')) {
          throw const PrivilegeInstallCancelled();
        }
        throw Exception('Privileged command failed: $err');
      }
    } finally {
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
  }
}

/// Thrown when the user dismisses the administrator dialog during install.
class PrivilegeInstallCancelled implements Exception {
  const PrivilegeInstallCancelled();
  @override
  String toString() => 'Administrator permission was cancelled.';
}
