import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'vpn/openvpn_locator.dart';
import 'vpn/privilege_helper.dart';
import 'vpn/vpn_controller.dart';
import 'vpn/vpn_controller_factory.dart';
import 'vpn/vpn_models.dart';
import 'widgets/activity_log.dart';
import 'widgets/connect_orb.dart';
import 'widgets/profile_tile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  // Fire-and-forget: applies the saved choice once storage answers.
  themeController.load();
  runApp(QuickVpnRoot(themeController: themeController));
}

/// Owns the themed [MaterialApp] and rebuilds it when the theme choice changes.
class QuickVpnRoot extends StatelessWidget {
  final ThemeController themeController;

  const QuickVpnRoot({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.mode,
        home: QuickVpnApp(themeController: themeController),
      ),
    );
  }
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

class QuickVpnApp extends StatefulWidget {
  /// Optional injected controller (tests pass a fake). Production leaves this
  /// null and the platform factory picks the right engine.
  final VpnController? controller;

  /// Optional theme controller, used to surface the appearance setting. Null in
  /// tests (which mount the screen under their own [MaterialApp]).
  final ThemeController? themeController;

  const QuickVpnApp({super.key, this.controller, this.themeController});

  @override
  State<QuickVpnApp> createState() => _QuickVpnAppState();
}

class _QuickVpnAppState extends State<QuickVpnApp> {
  late final VpnController _vpn;
  StreamSubscription<VpnStage>? _stageSub;
  StreamSubscription<VpnStats>? _statsSub;

  final List<VpnProfile> _appendedProfiles = [];
  final List<LogEntry> _activity = [];
  int? _selectedProfileIndex;
  VpnStage _stage = VpnStage.disconnected;
  VpnStats _stats = VpnStats.zero;
  VpnReadiness? _readiness;
  bool _seamless = false;

  bool get _isConnected => _stage.isConnected;
  bool get _isMac => Platform.isMacOS;

  bool get _isBusy =>
      _stage == VpnStage.connecting ||
      _stage == VpnStage.authenticating ||
      _stage == VpnStage.gettingConfig ||
      _stage == VpnStage.assigningIp ||
      _stage == VpnStage.reconnecting ||
      _stage == VpnStage.exiting;

  @override
  void initState() {
    super.initState();
    _vpn = widget.controller ?? createVpnController();
    _stageSub = _vpn.stage.listen((s) {
      if (!mounted) return;
      if (s != _stage) _log(_stageMessage(s), level: _stageLevel(s));
      setState(() => _stage = s);
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
      if (!r.isReady && r.reason != null) {
        _log(r.reason!, level: LogLevel.warning);
      }
    }
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    _statsSub?.cancel();
    _vpn.dispose();
    super.dispose();
  }

  // --- activity log --------------------------------------------------------

  void _log(String message, {LogLevel level = LogLevel.info}) {
    if (!mounted) return;
    setState(() {
      _activity.add(LogEntry(message, level: level));
      // Cap history so a long-lived session can't grow unbounded.
      if (_activity.length > 200) _activity.removeAt(0);
    });
  }

  String _stageMessage(VpnStage s) {
    switch (s) {
      case VpnStage.connecting:
        return 'Connecting to server…';
      case VpnStage.authenticating:
        return 'Authenticating…';
      case VpnStage.gettingConfig:
        return 'Fetching configuration…';
      case VpnStage.assigningIp:
        return 'Assigning IP address…';
      case VpnStage.connected:
        return 'Tunnel established — connected';
      case VpnStage.reconnecting:
        return 'Connection dropped — reconnecting…';
      case VpnStage.exiting:
        return 'Disconnecting…';
      case VpnStage.disconnected:
        return 'Disconnected';
      case VpnStage.error:
        return 'Connection error';
    }
  }

  LogLevel _stageLevel(VpnStage s) {
    switch (s) {
      case VpnStage.connected:
        return LogLevel.success;
      case VpnStage.error:
        return LogLevel.error;
      case VpnStage.reconnecting:
        return LogLevel.warning;
      default:
        return LogLevel.info;
    }
  }

  // --- profile actions -----------------------------------------------------

  /// UI Action: Append a new profile to the application list
  Future<void> _handleAppendProfileAction() async {
    final FilePickerResult? fileResult = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ovpn'],
    );

    if (fileResult != null && fileResult.files.single.path != null) {
      final fileData = File(fileResult.files.single.path!);
      final textContents = await fileData.readAsString();
      final name = fileResult.files.single.name;

      setState(() {
        _appendedProfiles.add(
          VpnProfile(name: name, rawConfig: textContents),
        );
        if (_appendedProfiles.length == 1) _selectedProfileIndex = 0;
      });
      _log('Imported profile "$name"', level: LogLevel.success);
    }
  }

  /// Remove a profile, with an Undo affordance. Blocked while it's connected.
  void _removeProfile(int index) {
    if (_isConnected && index == _selectedProfileIndex) {
      _showMessage('Disconnect before removing this profile.');
      return;
    }
    final removed = _appendedProfiles[index];
    setState(() {
      _appendedProfiles.removeAt(index);
      final sel = _selectedProfileIndex;
      if (sel != null) {
        if (sel == index) {
          _selectedProfileIndex = _appendedProfiles.isEmpty ? null : 0;
        } else if (sel > index) {
          _selectedProfileIndex = sel - 1;
        }
      }
    });
    _log('Removed profile "${removed.name}"');

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${removed.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoRemove(index, removed),
          ),
        ),
      );
  }

  void _undoRemove(int index, VpnProfile profile) {
    setState(() {
      final i = index.clamp(0, _appendedProfiles.length);
      _appendedProfiles.insert(i, profile);
      _selectedProfileIndex ??= i;
    });
    _log('Restored profile "${profile.name}"');
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

    _log('Starting connection to "${profile.name}"');
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
      _log(e.message, level: LogLevel.error);
      _showMessage(e.message);
    } on PrivilegeRequestCancelled {
      _log('Administrator permission was cancelled', level: LogLevel.warning);
    } catch (e) {
      _log('Connect failed: $e', level: LogLevel.error);
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
      _log(
        ok ? 'Seamless connections enabled' : 'Could not enable seamless mode',
        level: ok ? LogLevel.success : LogLevel.warning,
      );
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

  // --- terminal tip --------------------------------------------------------

  /// A copy-pasteable bash script that connects the given profile with the
  /// OpenVPN CLI directly — so the profile is usable without QuickVPN.
  String _cliScriptFor(VpnProfile? profile) {
    final name = profile?.name ?? 'your-profile.ovpn';
    final auth = profile?.requiresAuth ?? false;
    final b = StringBuffer()
      ..writeln('#!/usr/bin/env bash')
      ..writeln('# Connect to "$name" with OpenVPN — no QuickVPN needed.')
      ..writeln('#')
      ..writeln('# 1) Install the openvpn client:')
      ..writeln('#      Debian/Ubuntu : sudo apt install -y openvpn')
      ..writeln('#      Fedora        : sudo dnf install -y openvpn')
      ..writeln('#      Arch          : sudo pacman -S openvpn')
      ..writeln('#      macOS (brew)  : brew install openvpn')
      ..writeln('#')
      ..writeln('# 2) cd into the folder that holds "$name", then run:');
    if (auth) {
      b.writeln('#    (you will be prompted for your username & password)');
    }
    b.write('sudo openvpn --config "$name"');
    return b.toString();
  }

  void _showCliTip() {
    final profile = _selectedProfileIndex != null
        ? _appendedProfiles[_selectedProfileIndex!]
        : null;
    final script = _cliScriptFor(profile);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetCtx.muted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.terminal_rounded,
                      color: AppColors.brandBlue, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Run from terminal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: sheetCtx.scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Prefer the command line? Connect with OpenVPN directly using '
                'this profile — handy on a Linux box or over SSH.',
                style: TextStyle(fontSize: 13, color: sheetCtx.muted),
              ),
              const SizedBox(height: 14),
              // The script.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sheetCtx.panelHi,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sheetCtx.hairline),
                ),
                child: SelectableText(
                  script,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.45,
                    color: sheetCtx.scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    // Capture before the async gap so no BuildContext is used
                    // across it.
                    final navigator = Navigator.of(sheetCtx);
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: script));
                    navigator.pop();
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                          content: Text('Command copied to clipboard')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy script'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- settings ------------------------------------------------------------

  void _openSettings() {
    final tc = widget.themeController;
    if (tc == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ListenableBuilder(
          listenable: tc,
          builder: (sheetCtx, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetCtx.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: sheetCtx.muted,
                    ),
                  ),
                ),
              ),
              _themeOption(sheetCtx, tc, ThemeMode.system, 'System',
                  Icons.brightness_auto_rounded),
              _themeOption(sheetCtx, tc, ThemeMode.light, 'Light',
                  Icons.light_mode_rounded),
              _themeOption(sheetCtx, tc, ThemeMode.dark, 'Dark',
                  Icons.dark_mode_rounded),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeOption(BuildContext ctx, ThemeController tc, ThemeMode mode,
      String label, IconData icon) {
    final selected = tc.mode == mode;
    return ListTile(
      leading: Icon(icon, color: selected ? AppColors.brandBlue : ctx.muted),
      title: Text(label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          )),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.brandBlue)
          : null,
      onTap: () => tc.setMode(mode),
    );
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedProfileIndex != null;
    final notReady = _readiness != null && !_readiness!.isReady;

    final orbLabel = !hasSelection
        ? 'Connect'
        : _isConnected
            ? 'Disconnect'
            : _isBusy
                ? _stage.label
                : 'Connect';

    return Scaffold(
      appBar: AppBar(
        title: SvgPicture.asset(
          context.isDark
              ? 'assets/quick_logo_dark.svg'
              : 'assets/quick_logo.svg',
          height: 30,
          semanticsLabel: 'Quick',
        ),
        actions: [
          if (_isMac && !notReady && !_seamless)
            IconButton(
              tooltip: "Make connections seamless (no password each time)",
              icon: const Icon(Icons.flash_on_outlined),
              onPressed: _makeSeamless,
            ),
          if (_isMac && _seamless)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: "Seamless connections enabled",
                child: Icon(Icons.flash_on, color: AppColors.warning),
              ),
            ),
          if (widget.themeController != null)
            IconButton(
              tooltip: "Settings",
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openSettings,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        // Scrolls as a whole so the layout never overflows on short or resized
        // windows — the hero, log and list all flow into one scroll view.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notReady) _readinessBanner(_readiness!),

              // Hero — status pill, connect orb, live stats / hint.
              _hero(hasSelection, orbLabel),

              const SizedBox(height: 18),

              // Activity log — "what the app is processing".
              ActivityLog(entries: _activity),

              const SizedBox(height: 20),

              // Profiles header.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      "Your Profiles",
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.scheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _handleAppendProfileAction,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text("Import .ovpn"),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Profile list / empty state. shrinkWrap + non-scrolling physics
              // so it sizes to its content and the outer view does the scrolling.
              if (_appendedProfiles.isEmpty)
                _emptyState()
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 2),
                  itemCount: _appendedProfiles.length,
                  itemBuilder: (ctx, index) {
                    final item = _appendedProfiles[index];
                    final isSelected = _selectedProfileIndex == index;
                    return ProfileTile(
                      name: item.name,
                      selected: isSelected,
                      requiresAuth: item.requiresAuth,
                      hasCredentials: item.hasCredentials,
                      connected: isSelected && _isConnected,
                      onTap: () {
                        if (!_isConnected) {
                          setState(() => _selectedProfileIndex = index);
                        }
                      },
                      onEditCredentials: () => _editCredentials(item),
                      onDelete: () => _removeProfile(index),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(bool hasSelection, String orbLabel) {
    final selectedName = hasSelection
        ? _appendedProfiles[_selectedProfileIndex!].name
        : null;

    return Column(
      children: [
        const SizedBox(height: 8),
        _statusPill(),
        const SizedBox(height: 16),
        ConnectOrb(
          enabled: hasSelection,
          connected: _isConnected,
          busy: _isBusy,
          label: orbLabel,
          onTap: hasSelection ? _toggleVpnConnection : null,
        ),
        const SizedBox(height: 14),
        if (_isConnected)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _statChip(Icons.timer_outlined, _fmtDuration(_stats.duration)),
              _statChip(Icons.south_rounded, _fmtBytes(_stats.bytesIn)),
              _statChip(Icons.north_rounded, _fmtBytes(_stats.bytesOut)),
            ],
          )
        else
          Text(
            selectedName ?? 'Select a profile to get started',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: context.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        const SizedBox(height: 6),
        // Power-user tip: the equivalent OpenVPN CLI command / bash script.
        TextButton.icon(
          onPressed: _showCliTip,
          icon: const Icon(Icons.terminal_rounded, size: 18),
          label: const Text('Run from terminal'),
          style: TextButton.styleFrom(foregroundColor: context.muted),
        ),
      ],
    );
  }

  Widget _statusPill() {
    final color = _statusColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            _stage.label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor() {
    if (_isConnected) return AppColors.connected;
    if (_stage == VpnStage.error) return AppColors.danger;
    if (_isBusy) return AppColors.warning;
    return context.muted;
  }

  Widget _statChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.muted),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 40, color: context.muted),
            const SizedBox(height: 12),
            Text(
              "No profiles added yet",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Import an .ovpn file to begin.",
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readinessBanner(VpnReadiness r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.reason ?? "Not ready",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.scheme.onSurface,
                    )),
                if (r.remediation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      r.remediation!,
                      style: TextStyle(
                        fontFamily: "monospace",
                        color: context.muted,
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
