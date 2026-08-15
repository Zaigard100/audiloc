import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/models/track.dart';
import '../../data/repositories/devices_repository.dart';
import '../../data/repositories/tracks_repository.dart';
import '../playback/player_service.dart';
import 'remote_control_models.dart';

/// Accepts WebSocket connections from other devices wanting to control
/// this one's playback — play/pause/next/previous, or loading a specific
/// track at a position. See docs/adr/0030-remote-playback-control.md.
///
/// Bound to all interfaces like the other sync servers (see
/// `ShareServer`'s doc) — a loopback-only bind would make this
/// unreachable from other devices on the LAN.
///
/// Every connecting device must already be paired to this profile
/// (present in [_devicesRepository], not just claiming an id in its
/// hello message) *and* [_isAllowed] must currently return `true` —
/// checked fresh on every connection attempt (not captured once at
/// server-start), so flipping the Settings toggle takes effect
/// immediately for new connection attempts. Existing connections aren't
/// force-closed when the toggle flips off mid-session — not worth the
/// extra bookkeeping for how rarely that timing would actually matter in
/// practice; the next reconnect (e.g. the controller's device coming back
/// online) picks up the new value.
class RemoteControlServer {
  RemoteControlServer({
    required PlayerService playerService,
    required DevicesRepository devicesRepository,
    required TracksRepository tracksRepository,
    required bool Function() isAllowed,
    this.port = 8546,
  })  : _playerService = playerService,
        _devicesRepository = devicesRepository,
        _tracksRepository = tracksRepository,
        _isAllowed = isAllowed;

  final PlayerService _playerService;
  final DevicesRepository _devicesRepository;
  final TracksRepository _tracksRepository;
  final bool Function() _isAllowed;
  final int port;

  HttpServer? _server;
  final _connections = <_RemoteConnection>{};

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
    if (request.uri.path != '/remote/control' || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _handleConnection(socket);
    } catch (_) {
      // Upgrade failed mid-handshake — nothing to clean up, the request
      // never became a usable socket.
    }
  }

  /// One persistent `listen()` for the whole connection, not `.first`
  /// followed by a second `.listen()` — `dart:io`'s `WebSocket` is
  /// single-subscription, so listening twice throws. The first message
  /// received is always treated as the hello handshake; every message
  /// after the connection is accepted is a command.
  void _handleConnection(WebSocket socket) {
    _RemoteConnection? connection;
    var helloReceived = false;

    void cleanUp() {
      connection?.dispose();
      if (connection != null) _connections.remove(connection);
    }

    socket.listen(
      (raw) async {
        if (!helloReceived) {
          helloReceived = true;
          connection = await _acceptHello(socket, raw);
          if (connection == null) {
            await socket.close();
          } else {
            _connections.add(connection!);
          }
          return;
        }
        final active = connection;
        if (active != null) await _handleIncomingMessage(active, raw);
      },
      onDone: cleanUp,
      onError: (_) => cleanUp(),
      cancelOnError: true,
    );
  }

  Future<_RemoteConnection?> _acceptHello(WebSocket socket, Object? raw) async {
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
    if (!paired || !_isAllowed()) {
      _send(socket, const {'type': 'rejected'});
      return null;
    }

    _send(socket, const {'type': 'accepted'});
    return _RemoteConnection(socket, _playerService)..start();
  }

  Future<void> _handleIncomingMessage(_RemoteConnection connection, Object? raw) async {
    if (raw is! String) return;
    final Map<String, Object?> json;
    try {
      json = jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return;
    }
    final command = RemoteCommand.fromJson(json);
    if (command == null) return;
    await _apply(connection, command);
  }

  Future<void> _apply(_RemoteConnection connection, RemoteCommand command) async {
    switch (command) {
      case RemotePlay():
        await _playerService.play();
      case RemotePause():
        await _playerService.pause();
      case RemoteNext():
        await _playerService.next();
      case RemotePrevious():
        await _playerService.previous();
      case RemoteLoadAndPlay(:final trackIds, :final startIndex, :final positionMs):
        if (startIndex < 0 || startIndex >= trackIds.length) return;
        final startId = trackIds[startIndex];
        // Resolve the whole queue, not just the one track being jumped
        // to — a single-track queue would leave next/previous with
        // nothing to move to. Tracks this device doesn't have locally
        // are dropped (same rule `MediaKitPlayerService.setQueue` already
        // applies to every queue), which can shift which index the
        // requested track ends up at — re-found by id, not position.
        final tracks = <Track>[];
        for (final id in trackIds) {
          final track = await _tracksRepository.byId(id);
          if (track != null && track.isAvailableLocally) tracks.add(track);
        }
        final resolvedIndex = tracks.indexWhere((t) => t.id == startId);
        if (resolvedIndex < 0) {
          _send(connection.socket, const {'type': 'error', 'reason': 'track_not_available'});
          return;
        }
        await _playerService.setQueue(
          tracks,
          startIndex: resolvedIndex,
          autoPlay: true,
          seekTo: Duration(milliseconds: positionMs),
        );
    }
  }

  void _send(WebSocket socket, Map<String, Object?> message) {
    try {
      socket.add(jsonEncode(message));
    } catch (_) {
      // Socket already closing — irrelevant, nothing to deliver to.
    }
  }

  Future<void> dispose() async {
    for (final connection in _connections.toList()) {
      connection.dispose();
    }
    _connections.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// One connected, already-accepted controller — pushes this device's live
/// playback state to it until the socket closes or [dispose] is called.
class _RemoteConnection {
  _RemoteConnection(this.socket, this._playerService);

  final WebSocket socket;
  final PlayerService _playerService;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Track?>? _trackSub;
  StreamSubscription<PlaybackPositionState>? _positionSub;
  Timer? _pushTimer;
  Duration _lastDuration = Duration.zero;

  void start() {
    // `positionStream`'s `PlaybackPositionState.duration` is the only
    // place `PlayerService` exposes duration at all (no plain synchronous
    // getter for it) — tracked here purely to fill in `RemoteState.durationMs`
    // on the next state push, not pushed on every tick itself (see the
    // periodic timer below).
    _positionSub = _playerService.positionStream.listen((state) => _lastDuration = state.duration);
    _pushState();
    _playingSub = _playerService.playingStream.listen((_) => _pushState());
    _trackSub = _playerService.currentTrackStream.listen((_) => _pushState());
    // Position alone doesn't get its own push per change — same
    // "no write/push storms" lesson already applied elsewhere
    // (docs/adr/0025, docs/adr/0029) — a plain once-a-second tick is
    // enough for a slowly-updating progress bar.
    _pushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pushState());
  }

  void _pushState() {
    final track = _playerService.currentTrack;
    try {
      socket.add(jsonEncode(RemoteState(
        trackId: track?.id,
        title: track?.displayTitle,
        artist: track?.displayArtist,
        positionMs: _playerService.position.inMilliseconds,
        durationMs: _lastDuration.inMilliseconds,
        isPlaying: _playerService.isPlaying,
      ).toJson()));
    } catch (_) {
      // Socket already closing — the onDone/onError handlers in
      // RemoteControlServer._handleConnection will clean this up shortly.
    }
  }

  void dispose() {
    _playingSub?.cancel();
    _trackSub?.cancel();
    _positionSub?.cancel();
    _pushTimer?.cancel();
  }
}
