/// The caller's role — a fixed, closed set of int-coded roles (higher code =
/// strictly more privilege). Each user has exactly one.
///
/// Wire shape everywhere a role appears: `{ "code": 700, "name": "Admin" }`.
/// Parsing keys off the numeric [code] (name is advisory), so a renamed label
/// server-side never breaks privilege comparisons. [unknown] is a forward-compat
/// fallback so a role the server adds later can never crash the client.
enum Role {
  superAdmin(800, 'SuperAdmin', 'Super Admin'),
  admin(700, 'Admin', 'Admin'),
  manager(300, 'Manager', 'Manager'),
  user(200, 'User', 'Scanner'),
  viewer(100, 'Viewer', 'Viewer'),
  unknown(0, 'Unknown', 'Unknown');

  const Role(this.code, this.wireName, this.label);

  /// The privilege code (higher = more privilege). `0` for [unknown].
  final int code;

  /// The canonical server name (`SuperAdmin` | `Admin` | `Manager` | `User` |
  /// `Viewer`) — the value emitted in the role wire object's `name`.
  final String wireName;

  /// Human-readable label for the UI (e.g. `User` is shown as "Scanner").
  final String label;

  /// Parses the `{ "code", "name" }` role wire object. Keys off `code`; falls
  /// back to matching `name` if the code is missing/unrecognized.
  static Role fromJson(Map<String, dynamic>? json) {
    if (json == null) return Role.unknown;
    final code = (json['code'] as num?)?.toInt();
    if (code != null) {
      final byCode = fromCode(code);
      if (byCode != Role.unknown) return byCode;
    }
    final name = json['name'] as String?;
    if (name != null) {
      for (final r in Role.values) {
        if (r != Role.unknown && r.wireName == name) return r;
      }
    }
    return Role.unknown;
  }

  /// Resolves a role from its numeric code, or [unknown] if no role has it.
  static Role fromCode(int code) {
    for (final r in Role.values) {
      if (r != Role.unknown && r.code == code) return r;
    }
    return Role.unknown;
  }

  /// True when this role is at least as privileged as [required] (by code).
  bool meets(Role required) => code >= required.code;

  Map<String, dynamic> toJson() => {'code': code, 'name': wireName};
}
