import 'package:dio/dio.dart';

import 'share_models.dart';

/// Sends share offers/responses to another device's [ShareServer]. See
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
class ShareClient {
  ShareClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<void> sendOffer({
    required String host,
    required int port,
    required String fromId,
    required String fromName,
    required List<ShareItemPreview> items,
  }) =>
      _dio.post<void>(
        'http://$host:$port/share/offer',
        data: {
          'id': fromId,
          'name': fromName,
          'items': [
            for (final item in items)
              {'trackId': item.trackId, 'title': item.title, 'artist': item.artist, 'album': item.album},
          ],
        },
      );

  Future<void> sendResponse({
    required String host,
    required int port,
    required String fromId,
    required String fromName,
    required bool accepted,
  }) =>
      _dio.post<void>(
        'http://$host:$port/share/response',
        data: {'id': fromId, 'name': fromName, 'accepted': accepted},
      );
}
