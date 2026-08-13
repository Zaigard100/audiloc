import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../models/track.dart';

/// CRUD over the `tracks` CRDT table.
///
/// Writes are plain local SQLite writes — the CRDT/HLC bookkeeping and
/// eventual P2P propagation happen transparently underneath (see
/// `services/sync/metadata`). Callers never need to think about conflicts:
/// `sql_crdt` resolves them by highest HLC on merge.
///
/// One exception, deliberately: the file path. `tracks.path` is a synced
/// column like any other, so if two devices independently import the same
/// content (same sha256 `id`) at different local paths, whichever import
/// has the later HLC clobbers the other device's path for the *whole*
/// row after sync — playback then opens a nonexistent file. Every read
/// here resolves the path through `track_locations` instead, a table
/// keyed `trackId:nodeId` so each device's own row survives merges from
/// other devices untouched. See docs/adr/0009-local-track-paths.md.
class TracksRepository {
  TracksRepository(this._crdt);

  final SqliteCrdt _crdt;

  static const _selectWithLocalPath = '''
    SELECT t.*, COALESCE(tl.path, t.path) AS path
    FROM tracks t
    LEFT JOIN track_locations tl
      ON tl.id = t.id || ':' || ?1 AND tl.is_deleted = 0
  ''';

  Stream<List<Track>> watchAll() => _crdt.watch('''
        $_selectWithLocalPath
        WHERE t.is_deleted = 0
        ORDER BY t.artist, t.album, t.title
      ''', () => [_crdt.nodeId]).map((rows) => rows.map(Track.fromRow).toList());

  Future<List<Track>> all() async {
    final rows = await _crdt.query('''
      $_selectWithLocalPath
      WHERE t.is_deleted = 0
    ''', [_crdt.nodeId]);
    return rows.map(Track.fromRow).toList();
  }

  Future<Track?> byId(String id) async {
    final rows = await _crdt.query('''
      $_selectWithLocalPath
      WHERE t.id = ?2 AND t.is_deleted = 0
    ''', [_crdt.nodeId, id]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  Future<bool> exists(String id) async {
    final rows =
        await _crdt.query('SELECT 1 FROM tracks WHERE id = ?1 AND is_deleted = 0', [id]);
    return rows.isNotEmpty;
  }

  /// Inserts a new track, or revives/updates one previously soft-deleted
  /// with the same content hash (re-import after removal, or the same file
  /// discovered again via Syncthing under a different path). [track.path]
  /// is recorded as *this device's* local path for the file — see the
  /// class doc for why that's not the same as trusting `tracks.path`.
  Future<void> upsert(Track track) async {
    await _crdt.execute('''
        INSERT INTO tracks
          (id, path, title, artist, album, genre, duration_ms, bitrate_kbps, cover_path, file_size, added_on_device)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        ON CONFLICT (id) DO UPDATE SET
          path = excluded.path,
          title = excluded.title,
          artist = excluded.artist,
          album = excluded.album,
          genre = excluded.genre,
          duration_ms = excluded.duration_ms,
          bitrate_kbps = excluded.bitrate_kbps,
          cover_path = excluded.cover_path,
          file_size = excluded.file_size,
          added_on_device = excluded.added_on_device,
          is_deleted = 0
      ''', [
      track.id,
      track.path,
      track.title,
      track.artist,
      track.album,
      track.genre,
      track.durationMs,
      track.bitrateKbps,
      track.coverPath,
      track.fileSize,
      track.addedOnDevice,
    ]);
    await _crdt.execute('''
        INSERT INTO track_locations (id, track_id, path)
          VALUES (?1, ?2, ?3)
        ON CONFLICT (id) DO UPDATE SET
          path = excluded.path,
          is_deleted = 0
      ''', ['${track.id}:${_crdt.nodeId}', track.id, track.path]);
  }

  Future<void> delete(String id) =>
      _crdt.execute('DELETE FROM tracks WHERE id = ?1', [id]);

  Future<List<String>> allGenres() async {
    final rows = await _crdt.query('''
      SELECT DISTINCT genre FROM tracks
      WHERE is_deleted = 0 AND genre IS NOT NULL AND genre != ''
      ORDER BY genre
    ''');
    return rows.map((r) => r['genre']! as String).toList();
  }
}
