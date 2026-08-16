import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/repositories/devices_repository.dart';
import 'playback_ownership_link.dart';

/// Accepts WebSocket connections from other sync-enabled paired devices
/// and hands each successfully-accepted [PlaybackOwnershipLink] to
/// [onAccepted] — see docs/adr/0033-playback-ownership-and-handoff.md.
///
/// Bound to all interfaces, same as every other sync server in this app.
/// Listens always, on every device — availability (like
/// `RemoteControlServer`) depends on a fresh per-connection check, not on
/// whether the server itself is up: [isSyncEnabled] is re-read for every
/// hello, so flipping the profile-wide sync toggle takes effect
/// immediately for new connection attempts.
class PlaybackOwnershipServer {
  PlaybackOwnershipServer({
    required DevicesRepository devicesRepository,
    required bool Function() isSyncEnabled,
    this.port = 8547,
    this.bindAddress,
  })  : _devicesRepository = devicesRepository,
        _isSyncEnabled = isSyncEnabled;

  final DevicesRepository _devicesRepository;
  final bool Function() _isSyncEnabled;
  final int port;

  /// Defaults to [InternetAddress.anyIPv4] in production. Overridable
  /// only so tests can run two full peers in one process on distinct
  /// loopback addresses (127.0.0.1/127.0.0.2) while sharing the same
  /// port — real devices never need this, each already has its own IP.
  final InternetAddress? bindAddress;

  HttpServer? _server;
  final _acceptedController = StreamController<PlaybackOwnershipLink>.broadcast();

  Stream<PlaybackOwnershipLink> get onAccepted => _acceptedController.stream;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(bindAddress ?? InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_acceptLoop(server));
  }

  Future<void> _acceptLoop(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != '/playback-ownership' || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _handleConnection(socket);
    } catch (_) {
      // Upgrade failed mid-handshake — nothing to clean up.
    }
  }

  /// One persistent `listen()` for the whole connection — same
  /// single-subscription lesson `RemoteControlServer` already
  /// documents: the first message is always the hello handshake, every
  /// message after an established [PlaybackOwnershipLink] is forwarded
  /// to it via [PlaybackOwnershipLink.handleIncoming] rather than a
  /// second `.listen()` (see that class's doc for why).
  void _handleConnection(WebSocket socket) {
    PlaybackOwnershipLink? link;
    var helloReceived = false;

    void cleanUp() => link?.handleClosed();

    socket.listen(
      (raw) async {
        if (!helloReceived) {
          helloReceived = true;
          link = await _acceptHello(socket, raw);
          if (link == null) await socket.close();
          return;
        }
        link?.handleIncoming(raw);
      },
      onDone: cleanUp,
      onError: (_) => cleanUp(),
      cancelOnError: true,
    );
  }

  Future<PlaybackOwnershipLink?> _acceptHello(WebSocket socket, Object? raw) async {
    if (raw is! String) return null;
    final Map<String, Object?> hello;
    try {
      hello = jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
    if (hello['type'] != 'hello') return null;
    final deviceId = hello['deviceId'] as String?;
    if (deviceId == null) return null;

    final paired = await _devicesRepository.byId(deviceId) != null;
    if (!paired || !_isSyncEnabled()) {
      _send(socket, const {'type': 'rejected'});
      return null;
    }

    _send(socket, const {'type': 'accepted'});
    final link = PlaybackOwnershipLink(remoteDeviceId: deviceId, socket: socket);
    _acceptedController.add(link);
    return link;
  }

  void _send(WebSocket socket, Map<String, Object?> message) {
    try {
      socket.add(jsonEncode(message));
    } catch (_) {
      // Socket already closing.
    }
  }

  Future<void> dispose() async {
    await _acceptedController.close();
    await _server?.close(force: true);
    _server = null;
  }
}
