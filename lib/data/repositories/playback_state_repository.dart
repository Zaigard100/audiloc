import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../models/playback_state.dart';

/// CRUD over the `playback_state` table — always exactly one row (`id =
/// 'current'`), see [PlaybackState] and
/// docs/adr/0029-playback-state-sync.md.
class PlaybackStateRepository {
  PlaybackStateRepository(this._crdt);

  final SqliteCrdt _crdt;

  static const _id = 'current';

  Stream<PlaybackState?> watch() => _crdt
      .watch('SELECT * FROM playback_state WHERE id = ?1 AND is_deleted = 0', () => [_id])
      .map((rows) => rows.isEmpty ? null : PlaybackState.fromRow(rows.first));

  Future<PlaybackState?> get() async {
    final rows = await _crdt.query('SELECT * FROM playback_state WHERE id = ?1 AND is_deleted = 0', [_id]);
    return rows.isEmpty ? null : PlaybackState.fromRow(rows.first);
  }

  Future<void> save(PlaybackState state) => _crdt.execute('''
        INSERT INTO playback_state
          (id, track_id, position_ms, queue_type, playlist_id, device_id, device_name)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        ON CONFLICT (id) DO UPDATE SET
          track_id = excluded.track_id,
          position_ms = excluded.position_ms,
          queue_type = excluded.queue_type,
          playlist_id = excluded.playlist_id,
          device_id = excluded.device_id,
          device_name = excluded.device_name,
          is_deleted = 0
      ''', [
        _id,
        state.trackId,
        state.positionMs,
        state.queueType.name,
        state.playlistId,
        state.deviceId,
        state.deviceName,
      ]);
}
