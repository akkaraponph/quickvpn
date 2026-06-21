import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

void main() => runApp(
      const MaterialApp(
        home: QuickVpnApp(),
        debugShowCheckedModeBanner: false,
      ),
    );

class QuickVpnApp extends StatefulWidget {
  const QuickVpnApp({super.key});

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

  /// True when the config embeds a client certificate, so the OpenVPN engine
  /// must be told a cert is required (otherwise it injects
  /// `client-cert-not-required` and the handshake fails).
  bool get hasClientCert =>
      rawConfig.contains('<cert>') ||
      rawConfig.contains(RegExp(r'^\s*cert\s', multiLine: true));

  bool get hasCredentials => username?.isNotEmpty ?? false;
}

class _QuickVpnAppState extends State<QuickVpnApp> {
  late OpenVPN _engine;
  final List<VpnProfile> _appendedProfiles = [];
  int? _selectedProfileIndex;
  String _currentStage = "Disconnected";
  bool _isConnected = false;
  VpnStatus? _status; // Live throughput metrics

  @override
  void initState() {
    super.initState();
    _setupQuickVpnEngine();
  }

  Future<void> _setupQuickVpnEngine() async {
    _engine = OpenVPN(
      onVpnStageChanged: (stage, rawStage) {
        if (!mounted) return;
        setState(() {
          _currentStage = rawStage;
          _isConnected = rawStage.toLowerCase() == "connected";
        });
      },
      onVpnStatusChanged: (status) {
        if (!mounted || status == null) return;
        setState(() => _status = status);
      },
    );

    // openvpn_flutter only implements Android & iOS. On any other platform its
    // method/event channels have no native handler, so initialize() would throw
    // a MissingPluginException AND leak an async EventChannel "listen" error.
    // Skip init entirely there — the UI still runs and connecting is guarded.
    if (!(Platform.isAndroid || Platform.isIOS)) {
      debugPrint(
        "QuickVPN: VPN engine is Android/iOS-only; skipping init on this platform.",
      );
      return;
    }

    try {
      await _engine.initialize(
        groupIdentifier: "group.com.refactorroom.quickvpn",
        providerBundleIdentifier: "com.refactorroom.quickvpn.NetworkExtension",
        localizedDescription: "QuickVPN Engine",
      );
    } catch (e) {
      debugPrint("QuickVPN engine init failed: $e");
    }
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
        // Automatically highlight the new item if it's the first one loaded
        if (_appendedProfiles.length == 1) _selectedProfileIndex = 0;
      });
    }
  }

  Future<void> _toggleVpnConnection() async {
    if (_selectedProfileIndex == null) return;
    final profile = _appendedProfiles[_selectedProfileIndex!];

    if (_isConnected) {
      _engine.disconnect();
      return;
    }

    // openvpn_flutter only implements Android & iOS. Calling connect elsewhere
    // throws MissingPluginException, so fail fast with a clear explanation.
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _showMessage(
        "Connecting works on Android & iOS only — openvpn_flutter has no "
        "desktop implementation. Import/selection works here; run on an "
        "Android device to connect with these credentials.",
      );
      return;
    }

    // Profiles with `auth-user-pass` need a username/password first.
    if (profile.requiresAuth && !profile.hasCredentials) {
      final saved = await _editCredentials(profile);
      if (saved != true) return; // user cancelled
    }

    try {
      await _engine.connect(
        profile.rawConfig,
        profile.name,
        username: profile.username,
        password: profile.password,
        certIsRequired: profile.hasClientCert,
      );
    } catch (e) {
      _showMessage("Connect failed: $e");
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "⚡ QuickVPN",
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.blue),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: Main Status & Power Toggle Control
            Center(
              child: Column(
                children: [
                  Text(
                    "Status: ${_currentStage.toUpperCase()}",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isConnected ? Colors.green : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _selectedProfileIndex != null
                        ? _toggleVpnConnection
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: _selectedProfileIndex == null
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
                  // Live Metrics: real-time throughput indicators
                  if (_isConnected && _status != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _metric(Icons.timer_outlined, _status!.duration ?? "—"),
                        _metric(Icons.download_rounded, _status!.byteIn ?? "0"),
                        _metric(Icons.upload_rounded, _status!.byteOut ?? "0"),
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
}
