class Playlist {
  const Playlist({required this.id, required this.name, this.coverTrackId, this.coverPath});

  final String id;
  final String name;

  /// When set, this playlist's cover is one of its own tracks' cover art
  /// — see docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
  /// Synced like any other column; the actual local path is resolved
  /// through `track_locations`, same as [Track.coverPath], so this alone
  /// is safe to sync directly (it's just a reference, not a path).
  final String? coverTrackId;

  /// The resolved local path to display: either the referenced track's
  /// own cached cover ([coverTrackId] set), or a custom image this device
  /// has cached via `playlist_locations` ([coverTrackId] null). Never a
  /// synced column itself — see `PlaylistsRepository.watchPlaylists`.
  final String? coverPath;

  factory Playlist.fromRow(Map<String, Object?> row) => Playlist(
        id: row['id']! as String,
        name: row['name']! as String,
        coverTrackId: row['cover_track_id'] as String?,
        coverPath: (row['track_cover_path'] as String?) ?? (row['playlist_cover_path'] as String?),
      );
}
