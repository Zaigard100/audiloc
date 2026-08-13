/// A local account/profile — lets several people share one physical
/// device, each with their own library and their own set of paired
/// devices. See docs/adr/0013-account-profiles.md.
///
/// Deliberately **not** a CRDT model: this is purely local bookkeeping
/// (which profile directories exist on *this* device, which one is
/// active) — it never needs to sync anywhere, unlike everything a
/// profile's own database holds.
class Profile {
  const Profile({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
        id: json['id']! as String,
        name: json['name']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  Profile copyWith({String? name}) => Profile(id: id, name: name ?? this.name, createdAt: createdAt);
}
