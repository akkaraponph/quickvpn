import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'management_parser.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';

/// Shared desktop engine: writes the profile to a private temp dir, launches
/// the real `openvpn` binary (elevated), and drives it over OpenVPN's
/// management interface. Everything here is platform-neutral; the per-OS bits
/// — locating the binary, gaining root, how the daemon backgrounds itself —
/// are the abstract hooks below, implemented by the macOS / Linux / Windows
/// subclasses.
abstract class CliVpnController implements VpnController {
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  final _statsCtrl = StreamController<VpnStats>.broadcast();

  VpnStage _stage = VpnStage.disconnected;
  String? _openvpnPath;

  Socket? _mgmt;
  StreamSubscription<String>? _mgmtSub;
  Directory? _workDir;
  Timer? _ticker;
  DateTime? _connectedAt;
  int _bytesIn = 0;
  int _bytesOut = 0;
  VpnConnectionRequest? _request;

  // --- platform hooks ------------------------------------------------------

  /// Locate the openvpn binary for this platform (null when not installed).
  String? locateBinary();

  /// Readiness reason + remediation shown when [locateBinary] returns null.
  VpnReadiness whenBinaryMissing();

  /// Extra args controlling how the process backgrounds itself. Unix uses
  /// `--daemon`; Windows backgrounds via its launcher and returns `const []`.
  List<String> daemonizeArgs(String pidPath);

  /// Tighten the on-disk config's permissions (no-op where unsupported).
  Future<void> secureConfig(File configFile);

  /// Start [openvpn] with [args], elevated to root/admin. Must return once the
  /// daemon is launching; the management interface drives the rest. Throw
  /// [PrivilegeRequestCancelled] if the user dismisses the auth prompt.
  Future<void> launchElevated(
    String openvpn,
    List<String> args,
    Directory workDir,
  );

  // --- VpnController ---------------------------------------------------------

  @override
  Stream<VpnStage> get stage => _stageCtrl.stream;

  @override
  Stream<VpnStats> get stats => _statsCtrl.stream;

  @override
  VpnStage get currentStage => _stage;

  @override
  Future<void> initialize() async {
    _openvpnPath ??= locateBinary();
  }

  @override
  Future<VpnReadiness> checkReadiness() async {
    _openvpnPath ??= locateBinary();
    if (_openvpnPath == null) return whenBinaryMissing();
    return const VpnReadiness.ready();
  }

  @override
  Future<void> connect(VpnConnectionRequest request) async {
    _request = request;
    final openvpn = _openvpnPath ??= locateBinary();
    if (openvpn == null) {
      _emitStage(VpnStage.error);
      throw OpenVpnNotInstalled(
        whenBinaryMissing().remediation ?? 'openvpn is not installed',
      );
    }

    _emitStage(VpnStage.connecting);

    // Private work dir for config + log + pid (auto-cleaned on disconnect).
    final work = await Directory.systemTemp.createTemp('quickvpn_run');
    _workDir = work;
    final configPath = '${work.path}/profile.ovpn';
    final logPath = '${work.path}/openvpn.log';
    final pidPath = '${work.path}/openvpn.pid';
    final configFile = File(configPath);
    await configFile.writeAsString(request.config);
    await secureConfig(configFile);

    final port = await _freePort();

    final args = <String>[
      '--config', configPath,
      '--management', '127.0.0.1', '$port',
      '--management-hold',
      '--management-query-passwords',
      '--auth-nocache',
      '--log', logPath,
      '--verb', '3',
      ...daemonizeArgs(pidPath),
    ];

    try {
      await launchElevated(openvpn, args, work);
      await _attachManagement(port, logPath);
    } on PrivilegeRequestCancelled {
      await _cleanup();
      _emitStage(VpnStage.disconnected);
      rethrow;
    } catch (e) {
      await _cleanup();
      _emitStage(VpnStage.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final mgmt = _mgmt;
    if (mgmt != null) {
      try {
        mgmt.write('signal SIGTERM\n');
        await mgmt.flush();
      } catch (_) {
        // socket already gone — fall through to cleanup
      }
    }
    _emitStage(VpnStage.exiting);
    await _cleanup();
    _emitStage(VpnStage.disconnected);
  }

  @override
  void dispose() {
    _cleanup();
    _stageCtrl.close();
    _statsCtrl.close();
  }

  // --- shared helpers for subclasses ----------------------------------------

  /// `chmod 600` on the config (Unix). Best-effort.
  Future<void> chmod600(File file) async {
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {
      // best effort
    }
  }

  // --- internals -------------------------------------------------------------

  /// Connect to the management port (retrying while the daemon binds), then set
  /// up state/byte notifications and release the hold.
  Future<void> _attachManagement(int port, String logPath) async {
    Socket? socket;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (socket == null) {
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 600),
        );
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) {
          final hint = await _tailLog(logPath);
          throw Exception(
            'Could not reach the openvpn management interface.'
            '${hint.isEmpty ? '' : '\n$hint'}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    _mgmt = socket;
    _mgmtSub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onManagementLine,
          onError: (_) {},
          onDone: _onManagementClosed,
        );

    socket.write('state on\n');
    socket.write('bytecount 1\n');
    socket.write('hold release\n');
    await socket.flush();
  }

  void _onManagementLine(String line) {
    final event = parseManagementLine(line);
    if (event == null) return;

    switch (event) {
      case StageEvent(:final stage):
        _emitStage(stage);
        if (stage == VpnStage.connected) {
          _connectedAt = DateTime.now();
          _startTicker();
        } else if (stage == VpnStage.exiting) {
          _stopTicker();
        }
      case ByteCountEvent(:final bytesIn, :final bytesOut):
        _bytesIn = bytesIn;
        _bytesOut = bytesOut;
        _emitStats();
      case PasswordNeeded(:final realm):
        _sendCredentials(realm);
      case AuthFailed():
        _emitStage(VpnStage.error);
        disconnect();
      case HoldWaiting():
        _mgmt?.write('hold release\n');
    }
  }

  void _sendCredentials(String realm) {
    final mgmt = _mgmt;
    final req = _request;
    if (mgmt == null) return;
    final user = req?.username ?? '';
    final pass = req?.password ?? '';
    // Credentials travel only over the loopback management socket.
    mgmt.write('username "$realm" ${_mgmtEscape(user)}\n');
    mgmt.write('password "$realm" ${_mgmtEscape(pass)}\n');
    mgmt.flush();
  }

  /// Escape characters special to the management protocol's quoting.
  String _mgmtEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  void _onManagementClosed() {
    if (_stage != VpnStage.disconnected && _stage != VpnStage.exiting) {
      _emitStage(VpnStage.disconnected);
    }
    _stopTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _emitStats());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emitStats() {
    final dur = _connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(_connectedAt!);
    _statsCtrl
        .add(VpnStats(duration: dur, bytesIn: _bytesIn, bytesOut: _bytesOut));
  }

  void _emitStage(VpnStage stage) {
    _stage = stage;
    if (!_stageCtrl.isClosed) _stageCtrl.add(stage);
  }

  Future<void> _cleanup() async {
    _stopTicker();
    await _mgmtSub?.cancel();
    _mgmtSub = null;
    try {
      _mgmt?.destroy();
    } catch (_) {}
    _mgmt = null;
    _connectedAt = null;
    _bytesIn = 0;
    _bytesOut = 0;
    final work = _workDir;
    _workDir = null;
    if (work != null) {
      await work.delete(recursive: true).catchError((_) => work);
    }
  }

  Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  Future<String> _tailLog(String logPath) async {
    try {
      final lines = await File(logPath).readAsLines();
      final tail = lines.length <= 6 ? lines : lines.sublist(lines.length - 6);
      return tail.join('\n');
    } catch (_) {
      return '';
    }
  }
}
