class SyncthingDevice {
  const SyncthingDevice({
    required this.deviceId,
    required this.name,
    this.addresses = const ['dynamic'],
  });

  final String deviceId;
  final String name;
  final List<String> addresses;

  Map<String, dynamic> toJson() => {
        'deviceID': deviceId,
        'name': name,
        'addresses': addresses,
      };

  factory SyncthingDevice.fromJson(Map<String, dynamic> json) => SyncthingDevice(
        deviceId: json['deviceID'] as String,
        name: json['name'] as String? ?? '',
        addresses: (json['addresses'] as List?)?.cast<String>() ?? const ['dynamic'],
      );
}

class SyncthingFolder {
  const SyncthingFolder({
    required this.id,
    required this.label,
    required this.path,
    this.deviceIds = const [],
  });

  final String id;
  final String label;
  final String path;
  final List<String> deviceIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'path': path,
        'devices': [for (final id in deviceIds) {'deviceID': id}],
      };

  factory SyncthingFolder.fromJson(Map<String, dynamic> json) => SyncthingFolder(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        path: json['path'] as String? ?? '',
        deviceIds: ((json['devices'] as List?) ?? const [])
            .map((d) => (d as Map)['deviceID'] as String)
            .toList(),
      );
}
