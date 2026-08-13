import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

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
      lastOnlineAt: current.lastOnlineAt,
    ));
  }

  String _defaultDeviceName() {
    try {
      final host = Platform.localHostname;
      // Android doesn't expose a real hostname through this API — it
      // reliably returns "localhost", which is actively misleading once
      // shown as a *peer's* name on someone else's Devices screen.
      if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    } catch (_) {
      // Unsupported on some platforms; fall through to the default below.
    }
    final label = switch (Platform.operatingSystem) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'linux' => 'Linux',
      'windows' => 'Windows',
      'macos' => 'Mac',
      _ => 'Устройство',
    };
    // A short suffix so multiple devices on the same OS stay
    // distinguishable in the list instead of all showing the same label.
    return '$label (${deviceId.substring(0, 4)})';
  }
}

/// Platform + a concrete identifier for *this* installation — Android's
/// device model, or the desktop hostname. Appended to the profile name
/// (see [composeDeviceName]) so two devices sharing one profile
/// (docs/adr/0013-account-profiles.md, docs/adr/0016-device-label.md)
/// don't show up as identical, indistinguishable entries in each other's
/// "Устройства" list. A plain top-level function, not a method, so it can
/// serve as a default parameter value (a compile-time constant) while
/// still being swappable for a deterministic stub in tests.
Future<String> platformDeviceLabel() async {
  if (Platform.isAndroid) {
    final info = await DeviceInfoPlugin().androidInfo;
    return 'Android ${info.model}';
  }
  final label = switch (Platform.operatingSystem) {
    'ios' => 'iPhone',
    'linux' => 'Linux',
    'windows' => 'Windows',
    'macos' => 'Mac',
    _ => 'Устройство',
  };
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') return '$label $host';
  } catch (_) {
    // Unsupported on some platforms; fall through to the bare label.
  }
  return label;
}

/// `"<profile name> (<platform label>)"` — the name this device registers
/// for itself and advertises to peers. See [platformDeviceLabel].
String composeDeviceName(String profileName, String platformLabel) => '$profileName ($platformLabel)';
