import 'dart:io';

import 'base_cli_vpn_controller.dart';
import 'openvpn_locator.dart';
import 'privilege_helper.dart';
import 'vpn_controller.dart';

/// macOS engine: drives the real `openvpn` binary (no Swift, no Network
/// Extension) and controls it through OpenVPN's management interface. Gains
/// root through the native administrator dialog, or seamlessly via a
/// tightly-scoped sudoers rule the user can opt into.
class MacVpnController extends CliVpnController {
  @override
  String? locateBinary() =>
      locateOpenVpnOnSystem(candidates: defaultMacOpenVpnPaths);

  @override
  VpnReadiness whenBinaryMissing() => const VpnReadiness.notReady(
        'openvpn is not installed',
        remediation: 'Install it, then retry:  brew install openvpn',
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
    final seamless = await PrivilegeHelper.hasSeamlessSudo(openvpn);
    if (seamless) {
      // sudoers rule permits exactly this binary, NOPASSWD.
      final r = await Process.run('sudo', ['-n', openvpn, ...args]);
      if (r.exitCode != 0) {
        throw Exception('Failed to start openvpn (sudo): ${r.stderr}');
      }
      return;
    }

    // Dialog mode: run the launch through one administrator prompt. We exec the
    // command from a tiny script file to avoid nested-quote escaping in
    // AppleScript. openvpn --daemon forks and returns immediately.
    final cmd =
        '${PrivilegeHelper.shQuote(openvpn)} ${args.map(PrivilegeHelper.shQuote).join(' ')}';
    final scriptPath = '${workDir.path}/launch.sh';
    await File(scriptPath).writeAsString('#!/bin/sh\n$cmd\n');
    final apple =
        'do shell script "/bin/sh ${PrivilegeHelper.shQuote(scriptPath)}" with administrator privileges';
    final r = await Process.run('osascript', ['-e', apple]);
    if (r.exitCode != 0) {
      final err = '${r.stderr}';
      if (err.contains('-128') || err.contains('User canceled')) {
        throw const PrivilegeRequestCancelled();
      }
      throw Exception('Failed to start openvpn: $err');
    }
  }
}
