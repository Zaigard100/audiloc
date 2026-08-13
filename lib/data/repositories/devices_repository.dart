import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../models/device.dart';

/// CRUD over the `devices` table: the *known* peers this installation has
/// ever paired with. Live online/offline state is not stored here — see
/// `services/sync/discovery/discovery_service.dart`.
class DevicesRepository {
  DevicesRepository(this._crdt);

  final SqliteCrdt _crdt;

  Stream<List<Device>> watchAll() => _crdt
      .watch('SELECT * FROM devices WHERE is_deleted = 0 ORDER BY name')
      .map((rows) => rows.map(Device.fromRow).toList());

  Future<Device?> byId(String id) async {
    final rows =
        await _crdt.query('SELECT * FROM devices WHERE id = ?1 AND is_deleted = 0', [id]);
    return rows.isEmpty ? null : Device.fromRow(rows.first);
  }

  Future<void> upsert(Device device) => _crdt.execute('''
        INSERT INTO devices (id, name, host, sync_port, last_online_at)
          VALUES (?1, ?2, ?3, ?4, ?5)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name,
          host = excluded.host,
          sync_port = excluded.sync_port,
          last_online_at = excluded.last_online_at,
          is_deleted = 0
      ''', [
        device.id,
        device.name,
        device.host,
        device.syncPort,
        device.lastOnlineAt,
      ]);

  Future<void> touchLastOnline(String id, DateTime at) => _crdt.execute('''
        UPDATE devices SET last_online_at = ?1 WHERE id = ?2
      ''', [at.millisecondsSinceEpoch, id]);

  Future<void> delete(String id) =>
      _crdt.execute('DELETE FROM devices WHERE id = ?1', [id]);
}
