import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../models/playlist_track.dart';
import '../models/track.dart';

const _positionGap = 1000.0;

/// CRUD over `playlists` and `playlist_tracks`.
///
/// Track order uses fractional indexing: inserting/moving a track only
/// writes *that* row's `position`, computed as the midpoint between its new
/// neighbours. This keeps concurrent offline edits cheap and usually
/// non-conflicting, but it's still an eventual-consistency approximation,
/// not a true RGA — see docs/data-model.md and ТЗ п.9 for why a "perfect"
/// merge would need more (out of scope for the MVP).
class PlaylistsRepository {
  PlaylistsRepository(this._crdt);

  final SqliteCrdt _crdt;
  final _uuid = const Uuid();

  Stream<List<Playlist>> watchPlaylists() => _crdt
      .watch('SELECT * FROM playlists WHERE is_deleted = 0 ORDER BY name')
      .map((rows) => rows.map(Playlist.fromRow).toList());

  Future<Playlist> create(String name) async {
    final id = _uuid.v4();
    await _crdt.execute('''
      INSERT INTO playlists (id, name) VALUES (?1, ?2)
    ''', [id, name]);
    return Playlist(id: id, name: name);
  }

  Future<void> rename(String id, String name) => _crdt.execute('''
        UPDATE playlists SET name = ?1 WHERE id = ?2
      ''', [name, id]);

  Future<void> delete(String id) async {
    await _crdt.execute('DELETE FROM playlists WHERE id = ?1', [id]);
    final entries = await _crdt.query(
      'SELECT id FROM playlist_tracks WHERE playlist_id = ?1 AND is_deleted = 0',
      [id],
    );
    for (final row in entries) {
      await _crdt.execute(
        'DELETE FROM playlist_tracks WHERE id = ?1',
        [row['id']],
      );
    }
  }

  /// Ordered tracks for a playlist, joined against `tracks` so deleted or
  /// still-syncing tracks (no local row yet) are silently skipped. `path`
  /// and `cover_path` are resolved through `track_locations` the same way
  /// `TracksRepository` does — see its class doc for why the raw
  /// `tracks.path`/`tracks.cover_path` columns aren't safe to trust
  /// as-is.
  Stream<List<Track>> watchTracks(String playlistId) => _crdt.watch('''
        SELECT t.*, tl.path AS path, tl.cover_path AS cover_path FROM playlist_tracks pt
        JOIN tracks t ON t.id = pt.track_id AND t.is_deleted = 0
        LEFT JOIN track_locations tl ON tl.id = t.id || ':' || ?2 AND tl.is_deleted = 0
        WHERE pt.playlist_id = ?1 AND pt.is_deleted = 0
        ORDER BY pt.position
      ''', () => [playlistId, _crdt.nodeId]).map((rows) => rows.map(Track.fromRow).toList());

  /// Like [watchTracks], but keeps each row's `playlist_tracks.id` and
  /// `position` so the UI can remove *this* occurrence of a track, or
  /// compute a new fractional position for drag-and-drop reordering
  /// (`PlaylistDetailScreen`'s `ReorderableListView` — see [moveEntry]),
  /// without an extra query.
  Stream<List<PlaylistItem>> watchItems(String playlistId) => _crdt.watch('''
        SELECT pt.id AS entry_id, pt.position AS position, t.*, tl.path AS path, tl.cover_path AS cover_path
        FROM playlist_tracks pt
        JOIN tracks t ON t.id = pt.track_id AND t.is_deleted = 0
        LEFT JOIN track_locations tl ON tl.id = t.id || ':' || ?2 AND tl.is_deleted = 0
        WHERE pt.playlist_id = ?1 AND pt.is_deleted = 0
        ORDER BY pt.position
      ''', () => [playlistId, _crdt.nodeId]).map((rows) => rows.map(PlaylistItem.fromRow).toList());

  Stream<List<PlaylistTrack>> watchEntries(String playlistId) => _crdt.watch('''
        SELECT * FROM playlist_tracks
        WHERE playlist_id = ?1 AND is_deleted = 0
        ORDER BY position
      ''', () => [playlistId]).map((rows) => rows.map(PlaylistTrack.fromRow).toList());

  Future<void> addTrack(String playlistId, String trackId) async {
    final rows = await _crdt.query('''
      SELECT MAX(position) AS max_position FROM playlist_tracks
      WHERE playlist_id = ?1 AND is_deleted = 0
    ''', [playlistId]);
    final maxPosition = (rows.first['max_position'] as num?)?.toDouble() ?? 0;
    await _crdt.execute('''
      INSERT INTO playlist_tracks (id, playlist_id, track_id, position)
        VALUES (?1, ?2, ?3, ?4)
    ''', [_uuid.v4(), playlistId, trackId, maxPosition + _positionGap]);
  }

  Future<void> removeEntry(String entryId) =>
      _crdt.execute('DELETE FROM playlist_tracks WHERE id = ?1', [entryId]);

  /// Moves [entryId] to sit between [beforePosition] and [afterPosition]
  /// (either may be null when moving to an end of the list).
  Future<void> moveEntry(
    String entryId, {
    double? beforePosition,
    double? afterPosition,
  }) async {
    final double newPosition;
    if (beforePosition == null && afterPosition == null) {
      newPosition = _positionGap;
    } else if (beforePosition == null) {
      newPosition = afterPosition! - _positionGap;
    } else if (afterPosition == null) {
      newPosition = beforePosition + _positionGap;
    } else {
      newPosition = (beforePosition + afterPosition) / 2;
    }
    await _crdt.execute('''
      UPDATE playlist_tracks SET position = ?1 WHERE id = ?2
    ''', [newPosition, entryId]);
  }
}
