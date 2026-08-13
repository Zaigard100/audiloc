import 'package:dio/dio.dart';

/// Sends pairing requests/responses to another device's [PairingServer].
/// See docs/adr/0011-mutual-pairing-confirmation.md.
class PairingClient {
  PairingClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<void> sendRequest({
    required String host,
    required int port,
    required String fromId,
    required String fromName,
  }) =>
      _dio.post<void>('http://$host:$port/pair/request', data: {'id': fromId, 'name': fromName});

  Future<void> sendResponse({
    required String host,
    required int port,
    required String fromId,
    required String fromName,
    required bool accepted,
  }) =>
      _dio.post<void>(
        'http://$host:$port/pair/response',
        data: {'id': fromId, 'name': fromName, 'accepted': accepted},
      );
}
