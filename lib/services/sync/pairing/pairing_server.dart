import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing_models.dart';

/// Receives pairing requests/responses from other devices over plain HTTP
/// — the other half of [PairingService]'s handshake (see
/// docs/adr/0011-mutual-pairing-confirmation.md). Bound to all interfaces
/// like `MetadataSyncService`/`FileTransferServer` — same reasoning: a
/// loopback-only bind would make this unreachable from other devices on
/// the LAN.
///
/// Both endpoints just acknowledge and return — nothing here blocks on the
/// user actually looking at a dialog. The request stays "pending" purely
/// in [PairingService]'s in-memory state until [PairingService.approve]
/// or [PairingService.reject] fires a follow-up call to the other side.
class PairingServer {
  PairingServer({this.port = 8543});

  final int port;

  HttpServer? _server;

  final _requestsController = StreamController<IncomingPairingRequest>.broadcast();
  final _responsesController = StreamController<PairingResponse>.broadcast();

  Stream<IncomingPairingRequest> get requests => _requestsController.stream;
  Stream<PairingResponse> get responses => _responsesController.stream;

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
      if (request.method != 'POST' || (path != '/pair/request' && path != '/pair/response')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
      final id = body['id'] as String?;
      final name = body['name'] as String?;
      final profileHash = body['profileHash'] as String?;
      // The client's own remote address, not anything the body claims —
      // this is what a pairing decision actually gets sent back to.
      final host = request.connectionInfo?.remoteAddress.address;
      if (id == null || name == null || profileHash == null || host == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      if (path == '/pair/request') {
        _requestsController.add(
          IncomingPairingRequest(fromId: id, fromName: name, fromHost: host, profileHash: profileHash),
        );
      } else {
        final accepted = body['accepted'] == true;
        _responsesController.add(
          PairingResponse(fromId: id, fromName: name, fromHost: host, accepted: accepted, profileHash: profileHash),
        );
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
    await _requestsController.close();
    await _responsesController.close();
  }
}
