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
      version: 1,
      onCreate: _createSchema,
    );
    return AudilocDatabase._(crdt);
  }

  /// In-memory database for tests: fast, isolated, no filesystem access.
  static Future<AudilocDatabase> openInMemory() async {
    final crdt = await SqliteCrdt.openInMemory(
      version: 1,
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
        syncthing_device_id TEXT,
        last_online_at INTEGER,
        PRIMARY KEY (id)
      )
    ''');
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'audiloc.db');
  }

  Future<void> close() => crdt.close();
}
