/// A known peer device.
///
/// [id] is this installation's CRDT node id (see
/// `services/sync/device_identity_service.dart`) — a random identifier, not
/// an asymmetric keypair. It's the closest stable "public id" the MVP has;
/// see docs/adr/0006-device-identity-without-asymmetric-crypto.md.
///
/// Online/offline status is *not* stored here: it's live state owned by
/// `DiscoveryService`, merged with these rows in the devices provider.
class Device {
  const Device({
    required this.id,
    required this.name,
    this.host,
    this.syncPort,
    this.syncthingDeviceId,
    this.lastOnlineAt,
  });

  final String id;
  final String name;
  final String? host;
  final int? syncPort;
  final String? syncthingDeviceId;
  final int? lastOnlineAt;

  DateTime? get lastOnlineAtDate =>
      lastOnlineAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastOnlineAt!);

  factory Device.fromRow(Map<String, Object?> row) => Device(
        id: row['id']! as String,
        name: row['name']! as String,
        host: row['host'] as String?,
        syncPort: row['sync_port'] as int?,
        syncthingDeviceId: row['syncthing_device_id'] as String?,
        lastOnlineAt: row['last_online_at'] as int?,
      );
}
