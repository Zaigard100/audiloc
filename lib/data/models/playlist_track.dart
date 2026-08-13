import 'track.dart';

/// One entry in a playlist.
///
/// [position] uses fractional indexing (space left between neighbours on
/// insert) so a track can be moved between two others by writing a single
/// row with the midpoint value, instead of renumbering the whole playlist.
/// See docs/data-model.md for why this doesn't fully solve concurrent
/// offline reordering (ТЗ п.9) — it only makes divergence less likely.
class PlaylistTrack {
  const PlaylistTrack({
    required this.id,
    required this.playlistId,
    required this.trackId,
    required this.position,
  });

  final String id;
  final String playlistId;
  final String trackId;
  final double position;

  factory PlaylistTrack.fromRow(Map<String, Object?> row) => PlaylistTrack(
        id: row['id']! as String,
        playlistId: row['playlist_id']! as String,
        trackId: row['track_id']! as String,
        position: (row['position']! as num).toDouble(),
      );
}

/// A playlist entry joined with its track — what the UI actually renders
/// (needs [entryId] to let the user remove *this* occurrence of a track,
/// as opposed to the track itself).
class PlaylistItem {
  const PlaylistItem({required this.entryId, required this.track});

  final String entryId;
  final Track track;

  factory PlaylistItem.fromRow(Map<String, Object?> row) => PlaylistItem(
        entryId: row['entry_id']! as String,
        track: Track.fromRow(row),
      );
}
