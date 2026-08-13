import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../data/repositories/tracks_repository.dart';

/// Serves this device's local audio files and cover art to peers over
/// plain HTTP — `GET /tracks/<trackId>` (with HTTP range support for
/// resumable downloads) and `GET /covers/<trackId>` (small, single-shot,
/// no range support needed). Replaces the earlier design of shelling out
/// to an external Syncthing process (see
/// docs/adr/0010-built-in-file-transfer.md): AudiLoc only needs the LAN
/// connectivity it already has for metadata sync, no second app to
/// install.
///
/// Bound to all interfaces like `MetadataSyncService` — see that class's
/// doc for why binding only to loopback would make this pointless for
/// LAN transfer.
class FileTransferServer {
  FileTransferServer({required TracksRepository tracksRepository, this.port = 8542})
      : _tracksRepository = tracksRepository;

  final TracksRepository _tracksRepository;
  final int port;

  HttpServer? _server;

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
      final segments = request.uri.pathSegments;
      if (request.method != 'GET' || segments.length != 2) {
        await _respondNotFound(request);
        return;
      }

      switch (segments[0]) {
        case 'tracks':
          await _handleTrack(request, segments[1]);
        case 'covers':
          await _handleCover(request, segments[1]);
        default:
          await _respondNotFound(request);
      }
    } catch (_) {
      // Peer disconnected mid-transfer, file vanished between the exists()
      // check and the read, etc. — never let one bad request take the
      // accept loop down.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Response already closed/broken; nothing more to do.
      }
    }
  }

  Future<void> _handleTrack(HttpRequest request, String trackId) async {
    final track = await _tracksRepository.byId(trackId);
    final localPath = track?.path;
    if (track == null || localPath == null) {
      await _respondNotFound(request);
      return;
    }
    final file = File(localPath);
    if (!await file.exists()) {
      await _respondNotFound(request);
      return;
    }

    final length = await file.length();
    final response = request.response
      ..headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..headers.set('X-Original-Extension', p.extension(localPath))
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    final range = request.headers.value(HttpHeaders.rangeHeader);
    final parsedRange = range == null ? null : _parseRange(range, length);
    if (parsedRange != null) {
      final (start, end) = parsedRange;
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length')
        ..headers.contentLength = end - start + 1;
      await response.addStream(file.openRead(start, end + 1));
    } else {
      response.headers.contentLength = length;
      await response.addStream(file.openRead());
    }
    await response.close();
  }

  /// No range/resume support — cover art is small enough that a dropped
  /// connection just means the client retries from scratch.
  Future<void> _handleCover(HttpRequest request, String trackId) async {
    final track = await _tracksRepository.byId(trackId);
    final coverPath = track?.coverPath;
    if (track == null || coverPath == null) {
      await _respondNotFound(request);
      return;
    }
    final file = File(coverPath);
    if (!await file.exists()) {
      await _respondNotFound(request);
      return;
    }

    final response = request.response
      ..headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..headers.contentLength = await file.length();
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _respondNotFound(HttpRequest request) async {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  /// Parses a single `bytes=start-end` range (the only form real clients
  /// send for a resumed download); returns `null` for anything else,
  /// which callers treat as "serve the whole file".
  (int, int)? _parseRange(String header, int length) {
    if (!header.startsWith('bytes=')) return null;
    final parts = header.substring(6).split('-');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    if (start == null || start >= length) return null;
    final end = parts[1].isEmpty ? length - 1 : (int.tryParse(parts[1]) ?? length - 1);
    return (start, end.clamp(start, length - 1));
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
  }
}
