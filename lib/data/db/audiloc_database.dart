import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Opens the local CRDT-backed SQLite database and owns its schema.
///
/// Every table declared here automatically gains `is_deleted`, `hlc`,
/// `node_id` and `modified` columns from `sql_crdt` — see
/// docs/data-model.md. This installation's CRDT node id
/// ([SqliteCrdt.nodeId]) is derived from the HLC timestamps already stored
/// in the file, so it stays stable across restarts as long as the database
/// file persists (no separate identity storage needed for the CRDT layer
/// itself — see `DeviceIdentityService` for how the UI-facing device id is
/// derived from it).
class AudilocDatabase {
  AudilocDatabase._(this.crdt);

  final SqliteCrdt crdt;

  String get nodeId => crdt.nodeId;

  static Future<AudilocDatabase> open({String? path}) async {
    final dbPath = path ?? await _defaultPath();
    final crdt = await SqliteCrdt.open(
      dbPath,
      version: 5,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return AudilocDatabase._(crdt);
  }

  /// In-memory database for tests: fast, isolated, no filesystem access.
  static Future<AudilocDatabase> openInMemory() async {
    final crdt = await SqliteCrdt.openInMemory(
      version: 5,
      onCreate: _createSchema,
    );
    return AudilocDatabase._(crdt);
  }

  static Future<void> _createSchema(CrdtTableExecutor db, int version) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT NOT NULL,
        path TEXT NOT NULL,
        title TEXT,
        artist TEXT,
        album TEXT,
        genre TEXT,
        duration_ms INTEGER,
        bitrate_kbps INTEGER,
        cover_path TEXT,
        file_size INTEGER,
        added_on_device TEXT,
        PRIMARY KEY (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        track_id TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (track_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        cover_track_id TEXT,
        PRIMARY KEY (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_tracks (
        id TEXT NOT NULL,
        playlist_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        position REAL NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE devices (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        host TEXT,
        sync_port INTEGER,
        -- Unused since docs/adr/0010-built-in-file-transfer.md replaced
        -- the Syncthing-based design; kept rather than migrated away to
        -- avoid a schema churn for a column that does no harm sitting
        -- unused. No Dart-level field reads/writes it anymore.
        syncthing_device_id TEXT,
        last_online_at INTEGER,
        PRIMARY KEY (id)
      )
    ''');
    await _createTrackLocationsTable(db);
    await _createPlaylistLocationsTable(db);
    await _createPlaybackStateTable(db);
  }

  /// `track_locations` holds where *this device* actually has each track's
  /// file, keyed by `trackId:nodeId` so every device's own row survives
  /// CRDT merges untouched by other devices' rows for the same track —
  /// unlike `tracks.path`, which is a plain synced column and therefore
  /// "last HLC wins" for the *whole row*. Two devices independently
  /// importing the same content (same sha256 id) at different local paths
  /// used to end up with one device's path silently overwriting the
  /// other's after sync, causing playback to open a nonexistent file and
  /// (since media_kit skips unplayable queue entries) start a completely
  /// different track instead. See docs/adr/0009-local-track-paths.md.
  ///
  /// `cover_path` carries the exact same fix for cover art
  /// (docs/adr/0012-local-cover-paths.md): `tracks.cover_path` is a plain
  /// synced column too, so it's only ever trustworthy as "some device has
  /// cover art for this track", never as a literal path — the actual
  /// per-device cover path lives here instead, nullable, since a device
  /// can easily have the audio file without (yet) having the cover.
  static Future<void> _createTrackLocationsTable(CrdtTableExecutor db) => db.execute('''
        CREATE TABLE track_locations (
          id TEXT NOT NULL,
          track_id TEXT NOT NULL,
          path TEXT NOT NULL,
          cover_path TEXT,
          PRIMARY KEY (id)
        )
      ''');

  /// `playlist_locations` is `track_locations`' exact counterpart for a
  /// playlist's *custom* cover image (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md)
  /// — keyed `playlistId:nodeId` so each device's own cached copy of the
  /// image survives CRDT merges untouched. Only used when a playlist's
  /// cover is a picked file, not one of its own tracks' art — that case
  /// (`playlists.cover_track_id`) resolves through `track_locations`
  /// instead and needs no table of its own.
  static Future<void> _createPlaylistLocationsTable(CrdtTableExecutor db) => db.execute('''
        CREATE TABLE playlist_locations (
          id TEXT NOT NULL,
          playlist_id TEXT NOT NULL,
          cover_path TEXT,
          PRIMARY KEY (id)
        )
      ''');

  /// A single, deliberately-global row (`id = 'current'`, enforced by
  /// [PlaybackStateRepository]) — "what's currently loaded, and where" is
  /// a whole-profile concept, not something that makes sense to have one
  /// of per device. Being an ordinary CRDT-tracked table, last-write-wins
  /// by HLC already gives exactly the "only the single most recent
  /// pause across every device counts" semantics
  /// docs/adr/0029-playback-state-sync.md asks for, with no extra
  /// bookkeeping. `device_id`/`device_name` are denormalized at write
  /// time rather than resolved later via `devices` — simpler than
  /// reaching for `sql_crdt`'s own per-row `node_id` bookkeeping column,
  /// and survives the writing device later being unpaired/renamed.
  static Future<void> _createPlaybackStateTable(CrdtTableExecutor db) => db.execute('''
        CREATE TABLE playback_state (
          id TEXT NOT NULL,
          track_id TEXT NOT NULL,
          position_ms INTEGER NOT NULL,
          queue_type TEXT NOT NULL,
          playlist_id TEXT,
          device_id TEXT NOT NULL,
          device_name TEXT NOT NULL,
          PRIMARY KEY (id)
        )
      ''');

  static Future<void> _upgradeSchema(CrdtTableExecutor db, int from, int to) async {
    if (from < 2) {
      await _createTrackLocationsTable(db);
    }
    if (from < 3) {
      await db.execute('ALTER TABLE track_locations ADD COLUMN cover_path TEXT');
    }
    if (from < 4) {
      await db.execute('ALTER TABLE playlists ADD COLUMN cover_track_id TEXT');
      await _createPlaylistLocationsTable(db);
    }
    if (from < 5) {
      await _createPlaybackStateTable(db);
    }
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'audiloc.db');
  }

  Future<void> close() => crdt.close();
}
