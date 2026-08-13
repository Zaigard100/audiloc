import 'dart:convert';
import 'dart:io';

import 'package:audiloc/services/sync/files/syncthing_client.dart';
import 'package:audiloc/services/sync/files/syncthing_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// No live Syncthing instance exists in this environment, so these tests
/// run [SyncthingClient] against a small in-process HTTP server that
/// mimics the shape of Syncthing's REST responses. That verifies request
/// construction (auth header, paths, JSON (de)serialization) but *not*
/// that the assumed API shape matches a real Syncthing release — see
/// docs/roadmap.md.
void main() {
  late HttpServer server;
  late SyncthingClient client;
  String? receivedApiKey;

  setUp(() async {
    receivedApiKey = null;
    final handler = const Pipeline().addHandler((Request request) {
      receivedApiKey = request.headers['x-api-key'];
      final path = request.url.path;

      if (path == 'rest/system/ping') {
        return Response.ok('{"ping":"pong"}', headers: {'content-type': 'application/json'});
      }
      if (path == 'rest/system/status') {
        return Response.ok(jsonEncode({'myID': 'DEVICE-ID-123'}),
            headers: {'content-type': 'application/json'});
      }
      if (path == 'rest/config/devices' && request.method == 'GET') {
        return Response.ok(
          jsonEncode([
            {
              'deviceID': 'DEV1',
              'name': 'Laptop',
              'addresses': ['dynamic'],
            },
          ]),
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.startsWith('rest/config/devices/') && request.method == 'PUT') {
        return Response(200);
      }
      if (path == 'rest/config/folders' && request.method == 'GET') {
        return Response.ok(
          jsonEncode([
            {
              'id': 'music',
              'label': 'Music',
              'path': '/home/user/Music',
              'devices': [
                {'deviceID': 'DEV1'},
              ],
            },
          ]),
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == 'rest/db/scan') {
        return Response(200);
      }
      return Response.notFound('not found');
    });

    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    client = SyncthingClient(baseUrl: 'http://127.0.0.1:${server.port}', apiKey: 'secret-key');
  });

  tearDown(() => server.close(force: true));

  test('ping returns true on 200 and sends the API key header', () async {
    expect(await client.ping(), isTrue);
    expect(receivedApiKey, 'secret-key');
  });

  test('myDeviceId parses the status response', () async {
    expect(await client.myDeviceId(), 'DEVICE-ID-123');
  });

  test('listDevices parses the device list', () async {
    final devices = await client.listDevices();
    expect(devices, hasLength(1));
    expect(devices.single.deviceId, 'DEV1');
    expect(devices.single.name, 'Laptop');
  });

  test('addDevice PUTs to the per-device item endpoint without throwing', () async {
    await client.addDevice(const SyncthingDevice(deviceId: 'DEV2', name: 'Phone'));
  });

  test('listFolders parses folders with their shared devices', () async {
    final folders = await client.listFolders();
    expect(folders.single.id, 'music');
    expect(folders.single.deviceIds, ['DEV1']);
  });

  test('rescanFolder does not throw on success', () async {
    await client.rescanFolder('music');
  });

  test('ping returns false when nothing is listening', () async {
    final unreachable = SyncthingClient(baseUrl: 'http://127.0.0.1:1', apiKey: 'x');
    expect(await unreachable.ping(), isFalse);
  });
}
