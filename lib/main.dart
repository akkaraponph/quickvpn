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
  VpnProfile({required this.name, required this.rawConfig});
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

    // Native VPN extension may not be configured yet (e.g. running the UI on
    // macOS/desktop before the NetworkExtension target exists). Guard so the
    // interface still loads and profiles can be imported.
    try {
      await _engine.initialize(
        groupIdentifier: "group.com.refactorroom.quickvpn",
        providerBundleIdentifier: "com.refactorroom.quickvpn.NetworkExtension",
        localizedDescription: "QuickVPN Engine",
      );
    } catch (e) {
      debugPrint("QuickVPN engine not available on this platform yet: $e");
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

  void _toggleVpnConnection() {
    if (_selectedProfileIndex == null) return;

    if (_isConnected) {
      _engine.disconnect();
    } else {
      final targetProfile = _appendedProfiles[_selectedProfileIndex!];
      _engine.connect(
        targetProfile.rawConfig,
        targetProfile.name,
        certIsRequired: false,
      );
    }
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
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.blue)
                                : null,
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
