import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'vpn/openvpn_locator.dart';
import 'vpn/privilege_helper.dart';
import 'vpn/vpn_controller.dart';
import 'vpn/vpn_controller_factory.dart';
import 'vpn/vpn_models.dart';

void main() => runApp(
      const MaterialApp(
        home: QuickVpnApp(),
        debugShowCheckedModeBanner: false,
      ),
    );

class QuickVpnApp extends StatefulWidget {
  /// Optional injected controller (tests pass a fake). Production leaves this
  /// null and the platform factory picks the right engine.
  final VpnController? controller;

  const QuickVpnApp({super.key, this.controller});

  @override
  State<QuickVpnApp> createState() => _QuickVpnAppState();
}

/// Model to track individual appended profiles
class VpnProfile {
  final String name;
  final String rawConfig;
  String? username;
  String? password;

  VpnProfile({
    required this.name,
    required this.rawConfig,
    this.username,
    this.password,
  });

  /// True when the config asks for interactive credentials — a bare
  /// `auth-user-pass` directive (not an inline `<auth-user-pass>` block or a
  /// `auth-user-pass file.txt` reference).
  bool get requiresAuth =>
      rawConfig.contains(RegExp(r'^\s*auth-user-pass\s*$', multiLine: true));

  /// True when the config embeds a client certificate.
  bool get hasClientCert =>
      rawConfig.contains('<cert>') ||
      rawConfig.contains(RegExp(r'^\s*cert\s', multiLine: true));

  bool get hasCredentials => username?.isNotEmpty ?? false;
}

class _QuickVpnAppState extends State<QuickVpnApp> {
  late final VpnController _vpn;
  StreamSubscription<VpnStage>? _stageSub;
  StreamSubscription<VpnStats>? _statsSub;

  final List<VpnProfile> _appendedProfiles = [];
  int? _selectedProfileIndex;
  VpnStage _stage = VpnStage.disconnected;
  VpnStats _stats = VpnStats.zero;
  VpnReadiness? _readiness;
  bool _seamless = false;

  bool get _isConnected => _stage.isConnected;
  bool get _isMac => Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _vpn = widget.controller ?? createVpnController();
    _stageSub = _vpn.stage.listen((s) {
      if (mounted) setState(() => _stage = s);
    });
    _statsSub = _vpn.stats.listen((s) {
      if (mounted) setState(() => _stats = s);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _vpn.initialize();
    await _refreshReadiness();
  }

  Future<void> _refreshReadiness() async {
    final r = await _vpn.checkReadiness();
    var seamless = false;
    if (_isMac && r.isReady) {
      final path = locateOpenVpnOnSystem();
      if (path != null) seamless = await PrivilegeHelper.hasSeamlessSudo(path);
    }
    if (mounted) {
      setState(() {
        _readiness = r;
        _seamless = seamless;
      });
    }
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    _statsSub?.cancel();
    _vpn.dispose();
    super.dispose();
  }

  /// UI Action: Append a new profile to the application list
  Future<void> _handleAppendProfileAction() async {
    final FilePickerResult? fileResult = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ovpn'],
    );

    if (fileResult != null && fileResult.files.single.path != null) {
      final fileData = File(fileResult.files.single.path!);
      final textContents = await fileData.readAsString();

      setState(() {
        _appendedProfiles.add(
          VpnProfile(
            name: fileResult.files.single.name,
            rawConfig: textContents,
          ),
        );
        if (_appendedProfiles.length == 1) _selectedProfileIndex = 0;
      });
    }
  }

  Future<void> _toggleVpnConnection() async {
    if (_selectedProfileIndex == null) return;
    final profile = _appendedProfiles[_selectedProfileIndex!];

    if (_isConnected || _stage == VpnStage.connecting) {
      await _vpn.disconnect();
      return;
    }

    final readiness = _readiness;
    if (readiness != null && !readiness.isReady) {
      _showMessage(
        [readiness.reason, readiness.remediation]
            .whereType<String>()
            .join('\n'),
      );
      return;
    }

    if (profile.requiresAuth && !profile.hasCredentials) {
      final saved = await _editCredentials(profile);
      if (saved != true) return;
    }

    try {
      await _vpn.connect(VpnConnectionRequest(
        name: profile.name,
        config: profile.rawConfig,
        username: profile.username,
        password: profile.password,
        certIsRequired: profile.hasClientCert,
      ));
    } on OpenVpnNotInstalled catch (e) {
      await _refreshReadiness();
      _showMessage(e.message);
    } on PrivilegeRequestCancelled {
      // user dismissed the admin dialog — nothing to report
    } catch (e) {
      _showMessage("Connect failed: $e");
    }
  }

  Future<void> _makeSeamless() async {
    final path = locateOpenVpnOnSystem();
    if (path == null) {
      _showMessage(const OpenVpnNotInstalled().message);
      return;
    }
    try {
      final ok = await PrivilegeHelper.installSeamlessSudo(path);
      if (mounted) setState(() => _seamless = ok);
      _showMessage(ok
          ? "Seamless connections enabled — no password needed next time."
          : "Could not enable seamless connections.");
    } on PrivilegeInstallCancelled {
      // dismissed — no-op
    } catch (e) {
      _showMessage("Setup failed: $e");
    }
  }

  /// Edit the username / password stored on a profile. Returns true if saved.
  Future<bool?> _editCredentials(VpnProfile profile) {
    final userCtrl = TextEditingController(text: profile.username ?? '');
    final passCtrl = TextEditingController(text: profile.password ?? '');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Credentials · ${profile.name}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Username",
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                profile.username =
                    userCtrl.text.trim().isEmpty ? null : userCtrl.text.trim();
                profile.password =
                    passCtrl.text.isEmpty ? null : passCtrl.text;
              });
              Navigator.pop(ctx, true);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedProfileIndex != null;
    final notReady = _readiness != null && !_readiness!.isReady;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: SvgPicture.asset(
          'assets/qvpn_logo.svg',
          height: 32,
          semanticsLabel: 'Qvpn',
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          if (_isMac && !notReady && !_seamless)
            IconButton(
              tooltip: "Make connections seamless (no password each time)",
              icon: const Icon(Icons.flash_on_outlined),
              onPressed: _makeSeamless,
            ),
          if (_isMac && _seamless)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Tooltip(
                message: "Seamless connections enabled",
                child: Icon(Icons.flash_on, color: Colors.amber),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notReady) _readinessBanner(_readiness!),

            // Section 1: Main Status & Power Toggle Control
            Center(
              child: Column(
                children: [
                  Text(
                    "Status: ${_stage.label.toUpperCase()}",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isConnected ? Colors.green : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: hasSelection ? _toggleVpnConnection : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: !hasSelection
                            ? Colors.grey[300]
                            : (_isConnected ? Colors.green : Colors.blue),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isConnected
                            ? Icons.power_settings_new
                            : Icons.play_arrow,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isConnected)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _metric(Icons.timer_outlined,
                            _fmtDuration(_stats.duration)),
                        _metric(Icons.download_rounded,
                            _fmtBytes(_stats.bytesIn)),
                        _metric(Icons.upload_rounded,
                            _fmtBytes(_stats.bytesOut)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Section 2: Heading & Add Button Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Your Appended Profiles",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _handleAppendProfileAction,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text("Import .ovpn"),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Section 3: Interactive Profile List View Container
            Expanded(
              child: _appendedProfiles.isEmpty
                  ? Center(
                      child: Text(
                        "No profiles added yet. Import an .ovpn file to begin.",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _appendedProfiles.length,
                      itemBuilder: (ctx, index) {
                        final item = _appendedProfiles[index];
                        final isSelected = _selectedProfileIndex == index;
                        return Card(
                          elevation: isSelected ? 2 : 0,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey[200]!,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.vpn_lock,
                              color:
                                  isSelected ? Colors.blue : Colors.grey[400],
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.requiresAuth)
                                  IconButton(
                                    tooltip: "Set username & password",
                                    icon: Icon(
                                      item.hasCredentials
                                          ? Icons.vpn_key
                                          : Icons.vpn_key_outlined,
                                      color: item.hasCredentials
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    onPressed: () => _editCredentials(item),
                                  ),
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: Colors.blue),
                              ],
                            ),
                            onTap: () {
                              if (!_isConnected) {
                                setState(() => _selectedProfileIndex = index);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readinessBanner(VpnReadiness r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.reason ?? "Not ready",
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (r.remediation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      r.remediation!,
                      style: TextStyle(
                        fontFamily: "monospace",
                        color: Colors.grey[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _refreshReadiness,
            child: const Text("Recheck"),
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
}
