/// Model to track individual appended profiles, with JSON (de)serialization so
/// they can be persisted across launches.
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

  Map<String, dynamic> toJson() => {
        'name': name,
        'rawConfig': rawConfig,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
      };

  factory VpnProfile.fromJson(Map<String, dynamic> json) => VpnProfile(
        name: json['name'] as String,
        rawConfig: json['rawConfig'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
      );
}
