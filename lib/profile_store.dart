import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'vpn/vpn_profile.dart';

/// Persists imported profiles and the current selection to the application's
/// config store (shared_preferences — a per-app plist on macOS, equivalent
/// platform stores elsewhere) so nothing is lost between launches.
class ProfileStore {
  static const _profilesKey = 'profiles_v1';
  static const _selectedKey = 'selected_index_v1';

  Future<({List<VpnProfile> profiles, int? selectedIndex})> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profilesKey);
      if (raw == null) {
        return (profiles: <VpnProfile>[], selectedIndex: null);
      }
      final profiles = (jsonDecode(raw) as List)
          .map((e) => VpnProfile.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

      var selected = prefs.getInt(_selectedKey);
      if (selected != null && (selected < 0 || selected >= profiles.length)) {
        selected = null;
      }
      if (selected == null && profiles.isNotEmpty) selected = 0;

      return (profiles: profiles, selectedIndex: selected);
    } catch (_) {
      // Corrupt or unavailable storage — start clean rather than crash.
      return (profiles: <VpnProfile>[], selectedIndex: null);
    }
  }

  Future<void> save(List<VpnProfile> profiles, int? selectedIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _profilesKey,
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
      );
      if (selectedIndex != null) {
        await prefs.setInt(_selectedKey, selectedIndex);
      } else {
        await prefs.remove(_selectedKey);
      }
    } catch (_) {
      // Best effort — the in-memory list still works for this session.
    }
  }
}
