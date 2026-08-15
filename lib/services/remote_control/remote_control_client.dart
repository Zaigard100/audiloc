import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'remote_control_models.dart';

/// Connects to another (already-paired) device's `RemoteControlServer` and
/// exposes its live playback state, plus methods to send it commands. See
/// docs/adr/0030-remote-playback-control.md.
///
/// One `RemoteControlClient` per target device — `connect()` may only be
/// called once per instance.
class RemoteControlClient {
  WebSocket? _socket;
  StreamSubscription<Object?>? _sub;
  final _stateController = StreamController<RemoteState?>.broadcast();

  /// Live state pushes once accepted; emits `null` once the connection
  /// closes (so a listener can tell "still connected, nothing loaded"
  /// apart from "no longer connected").
  Stream<RemoteState?> get states => _stateController.stream;

  /// Connects and completes once the target has actually answered —
  /// `true` only if it accepted (already paired to this profile, and its
  /// "allow remote control" setting is currently on). `false` covers
  /// every other outcome — explicit rejection, connection failure, no
  /// answer within [timeout] — deliberately never throws: from the
  /// caller's point of view "can't confirm it allows control" and
  /// "explicitly declined" both mean the same thing, don't show controls.
  Future<bool> connect({
    required String host,
    required int port,
    required String selfId,
    required String selfName,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await WebSocket.connect('ws://$host:$port/remote/control').timeout(timeout);
      _socket = socket;
      socket.add(jsonEncode({'type': 'hello', 'deviceId': selfId, 'name': selfName}));

      final handshake = Completer<bool>();
      // One persistent `listen()` for the connection's whole lifetime —
      // the accept/reject reply is just the first message through it, not
      // a separate `.first` call (which would leave nothing listening
      // afterward — `WebSocket` is single-subscription, a second
      // `.listen()` later would throw).
      _sub = socket.listen(
        (raw) => _handleMessage(raw, handshake),
        onDone: () {
          if (!handshake.isCompleted) handshake.complete(false);
          _stateController.add(null);
        },
        onError: (_) {
          if (!handshake.isCompleted) handshake.complete(false);
        },
        cancelOnError: true,
      );

      return await handshake.future.timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  void _handleMessage(Object? raw, Completer<bool> handshake) {
    if (raw is! String) return;
    final Map<String, Object?> json;
    try {
      json = jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return;
    }

    if (!handshake.isCompleted) {
      final accepted = json['type'] == 'accepted';
      handshake.complete(accepted);
      if (!accepted) unawaited(_socket?.close());
      return;
    }

    if (json['type'] == 'state') {
      _stateController.add(RemoteState.fromJson(json));
    }
    // `error` messages (e.g. track_not_available) aren't surfaced to a
    // caller yet — nothing in the UI reads them; a future pass could plumb
    // a toast through if that turns out to be worth doing.
  }

  void _send(RemoteCommand command) {
    try {
      _socket?.add(jsonEncode(command.toJson()));
    } catch (_) {
      // Not connected (yet, or anymore) — nothing to send to.
    }
  }

  void play() => _send(const RemotePlay());
  void pause() => _send(const RemotePause());
  void next() => _send(const RemoteNext());
  void previous() => _send(const RemotePrevious());
  void loadAndPlay(String trackId, Duration position) =>
      _send(RemoteLoadAndPlay(trackId: trackId, positionMs: position.inMilliseconds));

  Future<void> dispose() async {
    await _sub?.cancel();
    await _socket?.close();
    await _stateController.close();
  }
}
