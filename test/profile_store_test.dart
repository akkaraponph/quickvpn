import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickvpn/profile_store.dart';
import 'package:quickvpn/vpn/vpn_profile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and restores profiles with credentials and selection', () async {
    final store = ProfileStore();
    await store.save([
      VpnProfile(
        name: 'home.ovpn',
        rawConfig: 'client\nauth-user-pass\n',
        username: 'alice',
        password: 's3cret',
      ),
      VpnProfile(name: 'work.ovpn', rawConfig: 'client\n'),
    ], 1);

    final loaded = await store.load();
    expect(loaded.profiles.length, 2);
    expect(loaded.profiles[0].name, 'home.ovpn');
    expect(loaded.profiles[0].username, 'alice');
    expect(loaded.profiles[0].password, 's3cret');
    expect(loaded.profiles[0].requiresAuth, isTrue);
    expect(loaded.profiles[1].username, isNull);
    expect(loaded.selectedIndex, 1);
  });

  test('empty store loads nothing', () async {
    final loaded = await ProfileStore().load();
    expect(loaded.profiles, isEmpty);
    expect(loaded.selectedIndex, isNull);
  });

  test('out-of-range saved selection falls back to the first profile', () async {
    final store = ProfileStore();
    await store.save([VpnProfile(name: 'a.ovpn', rawConfig: 'client')], 7);
    final loaded = await store.load();
    expect(loaded.selectedIndex, 0);
  });
}
