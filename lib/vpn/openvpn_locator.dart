import 'dart:io';

/// Paths where Homebrew installs the openvpn binary, most likely first.
/// (`sbin` is where the formula links it on both Apple Silicon and Intel.)
const List<String> defaultOpenVpnPaths = [
  '/opt/homebrew/sbin/openvpn', // Apple Silicon Homebrew
  '/usr/local/sbin/openvpn', // Intel Homebrew
  '/opt/homebrew/bin/openvpn',
  '/usr/local/bin/openvpn',
];

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

/// Production wiring: checks the real filesystem and `which openvpn` on PATH.
String? locateOpenVpnOnSystem() {
  return locateOpenVpn(
    exists: (p) => File(p).existsSync(),
    which: () {
      try {
        final result = Process.runSync('which', ['openvpn']);
        if (result.exitCode == 0) {
          final out = (result.stdout as String).trim();
          if (out.isNotEmpty) return out;
        }
      } catch (_) {
        // `which` unavailable — treat as not found.
      }
      return null;
    },
  );
}
