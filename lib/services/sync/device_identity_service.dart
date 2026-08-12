import 'dart:io';

import '../../data/db/audiloc_database.dart';
import '../../data/models/device.dart';
import '../../data/repositories/devices_repository.dart';

/// Establishes and persists this installation's identity: the CRDT node id
/// doubling as its "public" device id (see
/// docs/adr/0006-device-identity-without-asymmetric-crypto.md), plus a
/// human-friendly name shown to other devices during pairing.
///
/// [ensureSelfDevice] must run once at startup, before advertising or
/// importing anything. Its first call after a fresh install has a side
/// effect that matters beyond bookkeeping: writing a `devices` row is what
/// makes [AudilocDatabase.nodeId] stable across restarts — `sql_crdt`
/// derives the node id from the HLC of the last written row, and with zero
/// rows there's nothing yet to derive it from.
class DeviceIdentityService {
  DeviceIdentityService(this._db, this._devicesRepository);

  final AudilocDatabase _db;
  final DevicesRepository _devicesRepository;

  String get deviceId => _db.nodeId;

  Future<Device> ensureSelfDevice() async {
    final existing = await _devicesRepository.byId(deviceId);
    if (existing != null) return existing;

    final device = Device(id: deviceId, name: _defaultDeviceName());
    await _devicesRepository.upsert(device);
    return device;
  }

  Future<void> rename(String name) async {
    final current = await ensureSelfDevice();
    await _devicesRepository.upsert(Device(
      id: current.id,
      name: name,
      host: current.host,
      syncPort: current.syncPort,
      syncthingDeviceId: current.syncthingDeviceId,
      lastOnlineAt: current.lastOnlineAt,
    ));
  }

  String _defaultDeviceName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {
      // Unsupported on some platforms; fall through to the default below.
    }
    return 'Моё устройство';
  }
}
