/// A local account/profile — lets several people share one physical
/// device, each with their own library and their own set of paired
/// devices. See docs/adr/0013-account-profiles.md.
///
/// Deliberately **not** a CRDT model: this is purely local bookkeeping
/// (which profile directories exist on *this* device, which one is
/// active) — it never needs to sync anywhere, unlike everything a
/// profile's own database holds.
class Profile {
  const Profile({required this.id, required this.name, required this.createdAt, required this.profileHash});

  final String id;
  final String name;
  final DateTime createdAt;

  /// A stable identity shared by every device that has ever joined this
  /// profile via pairing — unlike [id] (purely local, generated fresh in
  /// each device's own registry), this is the same value everywhere the
  /// profile has been added. Generated once at creation and carried
  /// through the pairing handshake itself (docs/adr/0015), not synced
  /// via CRDT — it's what lets a device recognize "I already have a copy
  /// of this exact profile" instead of treating every pairing as two
  /// independent libraries to merge.
  final String profileHash;

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
        id: json['id']! as String,
        name: json['name']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        // Registries written before profileHash existed have none —
        // `id` was already a random, sufficiently-unique value, so it
        // doubles as a fine default rather than needing a real migration.
        profileHash: json['profileHash'] as String? ?? json['id']! as String,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'profileHash': profileHash,
      };

  Profile copyWith({String? name}) =>
      Profile(id: id, name: name ?? this.name, createdAt: createdAt, profileHash: profileHash);
}
