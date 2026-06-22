import 'dart:io';

/// macOS: Homebrew install locations, most likely first.
/// (`sbin` is where the formula links it on both Apple Silicon and Intel.)
const List<String> defaultMacOpenVpnPaths = [
  '/opt/homebrew/sbin/openvpn', // Apple Silicon Homebrew
  '/usr/local/sbin/openvpn', // Intel Homebrew
  '/opt/homebrew/bin/openvpn',
  '/usr/local/bin/openvpn',
];

/// Linux: distro package locations plus common manual installs.
const List<String> defaultLinuxOpenVpnPaths = [
  '/usr/sbin/openvpn',
  '/usr/bin/openvpn',
  '/sbin/openvpn',
  '/bin/openvpn',
  '/usr/local/sbin/openvpn',
  '/usr/local/bin/openvpn',
];

/// Windows: the OpenVPN community installer's default locations.
const List<String> defaultWindowsOpenVpnPaths = [
  r'C:\Program Files\OpenVPN\bin\openvpn.exe',
  r'C:\Program Files (x86)\OpenVPN\bin\openvpn.exe',
];

/// Back-compat alias (macOS defaults) for existing callers and tests.
const List<String> defaultOpenVpnPaths = defaultMacOpenVpnPaths;

/// Pure, testable discovery: returns the first existing candidate, else the
/// result of [which], else null. Injectable [exists]/[which] for tests.
String? locateOpenVpn({
  required bool Function(String path) exists,
  String? Function()? which,
  List<String> candidates = defaultOpenVpnPaths,
}) {
  for (final path in candidates) {
    if (exists(path)) return path;
  }
  return which?.call();
}

/// Production wiring: checks the real filesystem and the system PATH.
///
/// [candidates] defaults to the current platform's known install locations;
/// PATH lookup uses `where` on Windows and `which` everywhere else.
String? locateOpenVpnOnSystem({List<String>? candidates}) {
  return locateOpenVpn(
    candidates: candidates ?? _platformCandidates(),
    exists: (p) => File(p).existsSync(),
    which: _whichOpenVpnOnPath,
  );
}

List<String> _platformCandidates() {
  if (Platform.isMacOS) return defaultMacOpenVpnPaths;
  if (Platform.isWindows) return defaultWindowsOpenVpnPaths;
  return defaultLinuxOpenVpnPaths; // Linux and other Unixes.
}

String? _whichOpenVpnOnPath() {
  try {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(cmd, ['openvpn']);
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim();
      if (out.isNotEmpty) {
        // `where` can return several lines; take the first match.
        return out.split(RegExp(r'[\r\n]+')).first.trim();
      }
    }
  } catch (_) {
    // PATH lookup tool unavailable — treat as not found.
  }
  return null;
}
