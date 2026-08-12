import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../models/track.dart';

/// CRUD over the `tracks` CRDT table.
///
/// Writes are plain local SQLite writes — the CRDT/HLC bookkeeping and
/// eventual P2P propagation happen transparently underneath (see
/// `services/sync/metadata`). Callers never need to think about conflicts:
/// `sql_crdt` resolves them by highest HLC on merge.
class TracksRepository {
  TracksRepository(this._crdt);

  final SqliteCrdt _crdt;

  Stream<List<Track>> watchAll() => _crdt
      .watch('SELECT * FROM tracks WHERE is_deleted = 0 ORDER BY artist, album, title')
      .map((rows) => rows.map(Track.fromRow).toList());

  Future<List<Track>> all() async {
    final rows = await _crdt.query('SELECT * FROM tracks WHERE is_deleted = 0');
    return rows.map(Track.fromRow).toList();
  }

  Future<Track?> byId(String id) async {
    final rows = await _crdt
        .query('SELECT * FROM tracks WHERE id = ?1 AND is_deleted = 0', [id]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  Future<bool> exists(String id) async {
    final rows =
        await _crdt.query('SELECT 1 FROM tracks WHERE id = ?1 AND is_deleted = 0', [id]);
    return rows.isNotEmpty;
  }

  /// Inserts a new track, or revives/updates one previously soft-deleted
  /// with the same content hash (re-import after removal, or the same file
  /// discovered again via Syncthing under a different path).
  Future<void> upsert(Track track) => _crdt.execute('''
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
