import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_models.dart';

/// Receives share offers/responses from other devices over plain HTTP —
/// the other half of [ShareService]'s handshake. Deliberately separate
/// from [PairingServer]: unlike pairing, a share offer isn't restricted to
/// same-profile devices at all — see
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
///
/// Bound to all interfaces like the other sync servers — a loopback-only
/// bind would make this unreachable from other devices on the LAN.
class ShareServer {
  ShareServer({this.port = 8544});

  final int port;

  HttpServer? _server;

  final _offersController = StreamController<IncomingShareOffer>.broadcast();
  final _responsesController = StreamController<ShareResponse>.broadcast();

  Stream<IncomingShareOffer> get offers => _offersController.stream;
  Stream<ShareResponse> get responses => _responsesController.stream;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_acceptLoop(server));
  }

  Future<void> _acceptLoop(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method != 'POST' || (path != '/share/offer' && path != '/share/response')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
      final id = body['id'] as String?;
      final name = body['name'] as String?;
      // The client's own remote address, not anything the body claims —
      // this is what the accepted files actually get downloaded from.
      final host = request.connectionInfo?.remoteAddress.address;
      if (id == null || name == null || host == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      if (path == '/share/offer') {
        final rawItems = body['items'] as List<Object?>?;
        if (rawItems == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final items = [
          for (final raw in rawItems)
            () {
              final item = raw as Map<String, Object?>;
              return ShareItemPreview(
                trackId: item['trackId']! as String,
                title: item['title'] as String?,
                artist: item['artist'] as String?,
                album: item['album'] as String?,
              );
            }(),
        ];
        _offersController.add(IncomingShareOffer(fromId: id, fromName: name, fromHost: host, items: items));
      } else {
        final accepted = body['accepted'] == true;
        _responsesController.add(ShareResponse(fromId: id, fromName: name, fromHost: host, accepted: accepted));
      }

      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
    } catch (_) {
      // Malformed request from a peer, connection dropped mid-read, etc.
      // — never let one bad request take the accept loop down.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Response already closed/broken; nothing more to do.
      }
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    await _offersController.close();
    await _responsesController.close();
  }
}
