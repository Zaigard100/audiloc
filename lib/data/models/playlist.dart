class Playlist {
  const Playlist({required this.id, required this.name});

  final String id;
  final String name;

  factory Playlist.fromRow(Map<String, Object?> row) => Playlist(
        id: row['id']! as String,
        name: row['name']! as String,
      );
}
