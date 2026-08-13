import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../models/track.dart';

/// CRUD over the `tracks` CRDT table.
///
/// Writes are plain local SQLite writes — the CRDT/HLC bookkeeping and
/// eventual P2P propagation happen transparently underneath (see
/// `services/sync/metadata`). Callers never need to think about conflicts:
/// `sql_crdt` resolves them by highest HLC on merge.
///
/// One exception, deliberately: local file paths. `tracks.path` and
/// `tracks.cover_path` are synced columns like any other, so if two
/// devices independently import the same content (same sha256 `id`) at
/// different local paths, whichever import has the later HLC clobbers the
/// other device's path for the *whole* row after sync — playback then
/// opens a nonexistent file, and cover art shows a broken-image icon.
/// Every read here resolves [Track.path]/[Track.coverPath] through
/// `track_locations` instead, a table keyed `trackId:nodeId` so each
/// device's own row survives merges from other devices untouched — both
/// are `null` when *this* device has no row there, i.e. it knows the
/// track exists (metadata synced) but doesn't have that particular file
/// (yet). See docs/adr/0009-local-track-paths.md,
/// docs/adr/0010-built-in-file-transfer.md and
/// docs/adr/0012-local-cover-paths.md.
class TracksRepository {
  TracksRepository(this._crdt);

  final SqliteCrdt _crdt;

  static const _selectWithLocalPath = '''
    SELECT t.*, tl.path AS path, tl.cover_path AS cover_path
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
  /// with the same content hash (re-import after removal, or the same
  /// file arriving via [services/sync/files] under a different path).
  /// [track.path] is recorded as *this device's* local path for the
  /// file — see the class doc for why that's not the same as trusting
  /// `tracks.path`. Requires a non-null path: this is how a device
  /// declares "I have the actual file", not just metadata about it.
  Future<void> upsert(Track track) async {
    final localPath = track.path;
    assert(localPath != null, 'upsert() requires a local file path — this device has the file');

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
      localPath,
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
        INSERT INTO track_locations (id, track_id, path, cover_path)
          VALUES (?1, ?2, ?3, ?4)
        ON CONFLICT (id) DO UPDATE SET
          path = excluded.path,
          cover_path = excluded.cover_path,
          is_deleted = 0
      ''', ['${track.id}:${_crdt.nodeId}', track.id, localPath, track.coverPath]);
  }

  /// Records that *this* device has downloaded [track.path] for
  /// [track.id] without touching the rest of the track's metadata —
  /// used by the file-transfer client once a download completes.
  /// Equivalent to [upsert] when the track already exists, but doesn't
  /// require (or overwrite) tag data.
  Future<void> recordLocalFile(String trackId, String localPath) => _crdt.execute('''
        INSERT INTO track_locations (id, track_id, path)
          VALUES (?1, ?2, ?3)
        ON CONFLICT (id) DO UPDATE SET
          path = excluded.path,
          is_deleted = 0
      ''', ['$trackId:${_crdt.nodeId}', trackId, localPath]);

  /// Records that *this* device has cached [coverPath] for [trackId]'s
  /// cover art — see docs/adr/0012-local-cover-paths.md. A plain
  /// `UPDATE`, not an upsert: only ever called for a track this device
  /// already has a `track_locations` row for (it already has the audio
  /// file — see [watchMissingCovers]), so there's always a row to update.
  Future<void> recordLocalCover(String trackId, String coverPath) => _crdt.execute('''
        UPDATE track_locations SET cover_path = ?1, is_deleted = 0 WHERE id = ?2
      ''', [coverPath, '$trackId:${_crdt.nodeId}']);

  /// Soft-delete: hides the track from the library, but only flags the
  /// `tracks` row (`is_deleted = 1`) — the audio file itself is never
  /// touched, and the row (along with its `track_locations` path) is
  /// still there for [restore] or [watchDeleted].
  Future<void> delete(String id) =>
      _crdt.execute('DELETE FROM tracks WHERE id = ?1', [id]);

  /// Undoes [delete]. A plain `UPDATE` rather than a fresh [upsert]: the
  /// row's other fields are untouched, this only flips the flag back.
  Future<void> restore(String id) =>
      _crdt.execute('UPDATE tracks SET is_deleted = 0 WHERE id = ?1', [id]);

  Stream<List<Track>> watchDeleted() => _crdt.watch('''
        $_selectWithLocalPath
        WHERE t.is_deleted = 1
        ORDER BY t.modified DESC
      ''', () => [_crdt.nodeId]).map((rows) => rows.map(Track.fromRow).toList());

  /// Tracks known (via synced metadata) but not present as a file on this
  /// device — candidates for `services/sync/files` to fetch.
  Stream<List<Track>> watchMissingFiles() => _crdt.watch('''
        $_selectWithLocalPath
        WHERE t.is_deleted = 0 AND tl.path IS NULL
        ORDER BY t.modified DESC
      ''', () => [_crdt.nodeId]).map((rows) => rows.map(Track.fromRow).toList());

  /// Node ids of devices known (via synced `track_locations` rows — which
  /// propagate over the same metadata-sync channel as everything else)
  /// to have their own local copy of [trackId]. Doesn't imply that device
  /// is currently online or reachable — callers cross-reference with
  /// live discovery for that.
  Future<List<String>> peersWithLocalCopy(String trackId) async {
    final rows = await _crdt.query('''
      SELECT DISTINCT node_id FROM track_locations
      WHERE track_id = ?1 AND is_deleted = 0 AND node_id != ?2
    ''', [trackId, _crdt.nodeId]);
    return rows.map((r) => r['node_id']! as String).toList();
  }

  /// Tracks with cover art known to exist somewhere (`tracks.cover_path`
  /// non-null — used purely as a boolean hint here, see the class doc)
  /// and the audio file already local, but no locally cached cover yet —
  /// candidates for cover-art download. Deliberately requires the audio
  /// file first: no point fetching cosmetic cover art for a track that
  /// isn't even playable here yet.
  Stream<List<Track>> watchMissingCovers() => _crdt.watch('''
        $_selectWithLocalPath
        WHERE t.is_deleted = 0 AND t.cover_path IS NOT NULL
          AND tl.path IS NOT NULL AND tl.cover_path IS NULL
        ORDER BY t.modified DESC
      ''', () => [_crdt.nodeId]).map((rows) => rows.map(Track.fromRow).toList());

  /// Like [peersWithLocalCopy], but for cover art specifically — a peer
  /// can easily have the audio file without (yet) having cached the
  /// cover, or vice versa.
  Future<List<String>> peersWithLocalCover(String trackId) async {
    final rows = await _crdt.query('''
      SELECT DISTINCT node_id FROM track_locations
      WHERE track_id = ?1 AND is_deleted = 0 AND node_id != ?2 AND cover_path IS NOT NULL
    ''', [trackId, _crdt.nodeId]);
    return rows.map((r) => r['node_id']! as String).toList();
  }

  /// One-time repair, meant to run once at startup: a track imported by
  /// this device *before* `track_locations` existed (or before this
  /// device's [upsert] ever ran again since) has its real path sitting
  /// only in `tracks.path`, with no row of its own in `track_locations`
  /// — since [watchMissingFiles] no longer falls back to `tracks.path`
  /// (that column can just as easily hold a peer's path after sync), such
  /// a track would otherwise look permanently "missing" despite the file
  /// being right there. Only trusts `tracks.path` when the file actually
  /// exists at that path on *this* filesystem — never adopts it blind,
  /// which is exactly the bug docs/adr/0009 fixed in the first place.
  Future<void> backfillLocalFileLocations() async {
    final rows = await _crdt.query('''
      SELECT t.id, t.path FROM tracks t
      LEFT JOIN track_locations tl ON tl.id = t.id || ':' || ?1 AND tl.is_deleted = 0
      WHERE tl.id IS NULL AND t.is_deleted = 0
    ''', [_crdt.nodeId]);

    for (final row in rows) {
      final path = row['path'] as String?;
      if (path != null && await File(path).exists()) {
        await recordLocalFile(row['id']! as String, path);
      }
    }
  }

  /// Same idea as [backfillLocalFileLocations], for cover art: a track
  /// this device imported before `track_locations.cover_path` existed
  /// already has its cover cached on disk (`LibraryImportService` writes
  /// it at a deterministic `$trackId.cover` path in [coverCacheDir]) but
  /// no row tracking that. Only trusts a file that actually exists there
  /// — never `tracks.cover_path` itself, which is a different device's
  /// path as often as not. See docs/adr/0012-local-cover-paths.md.
  Future<void> backfillLocalCovers(Directory coverCacheDir) async {
    final rows = await _crdt.query('''
      SELECT t.id FROM tracks t
      JOIN track_locations tl ON tl.id = t.id || ':' || ?1 AND tl.is_deleted = 0
      WHERE t.is_deleted = 0 AND t.cover_path IS NOT NULL AND tl.cover_path IS NULL
    ''', [_crdt.nodeId]);

    for (final row in rows) {
      final id = row['id']! as String;
      final file = File(p.join(coverCacheDir.path, '$id.cover'));
      if (await file.exists()) {
        await recordLocalCover(id, file.path);
      }
    }
  }

  Future<List<String>> allGenres() async {
    final rows = await _crdt.query('''
      SELECT DISTINCT genre FROM tracks
      WHERE is_deleted = 0 AND genre IS NOT NULL AND genre != ''
      ORDER BY genre
    ''');
    return rows.map((r) => r['genre']! as String).toList();
  }
}
