import 'package:dio/dio.dart';

import 'syncthing_models.dart';

/// REST client for a locally-running Syncthing instance (ТЗ п.3,
/// "Передача самих аудиофайлов" → Syncthing external process + REST API).
///
/// AudiLoc never implements its own file transfer protocol: it only tells
/// Syncthing, via its local API, which peers and folders to share, and lets
/// Syncthing do chunked transfer, resume, and versioning on its own. This
/// client isn't exercised against a live Syncthing in this environment (no
/// `syncthing` binary here) — see `test/unit/services/syncthing_client_test.dart`
/// for the mock-server coverage that does exist, and docs/roadmap.md for
/// what live verification would still need.
class SyncthingClient {
  SyncthingClient({
    required String baseUrl,
    required String apiKey,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              headers: {'X-API-Key': apiKey},
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 5),
            ));

  final Dio _dio;

  Future<bool> ping() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/rest/system/ping');
      return res.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<String> myDeviceId() async {
    final res = await _dio.get<Map<String, dynamic>>('/rest/system/status');
    return res.data!['myID'] as String;
  }

  Future<List<SyncthingDevice>> listDevices() async {
    final res = await _dio.get<List<dynamic>>('/rest/config/devices');
    return (res.data ?? const [])
        .map((e) => SyncthingDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addDevice(SyncthingDevice device) =>
      _dio.put('/rest/config/devices/${device.deviceId}', data: device.toJson());

  Future<void> removeDevice(String deviceId) =>
      _dio.delete('/rest/config/devices/$deviceId');

  Future<List<SyncthingFolder>> listFolders() async {
    final res = await _dio.get<List<dynamic>>('/rest/config/folders');
    return (res.data ?? const [])
        .map((e) => SyncthingFolder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFolder(SyncthingFolder folder) =>
      _dio.put('/rest/config/folders/${folder.id}', data: folder.toJson());

  Future<void> rescanFolder(String folderId) =>
      _dio.post('/rest/db/scan', queryParameters: {'folder': folderId});
}
