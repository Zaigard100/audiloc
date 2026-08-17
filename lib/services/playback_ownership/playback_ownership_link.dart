import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'playback_ownership_models.dart';

/// One established, already-handshaken connection to another sync-enabled
/// paired device — symmetric (unlike `RemoteControlServer`/`Client`'s
/// controller/target split): either side can send a claim, gossip an
/// owner change, or heartbeat. See
/// docs/adr/0033-playback-ownership-and-handoff.md.
///
/// Deliberately does **not** call `socket.listen()` itself —
/// `dart:io`'s `WebSocket` tolerates exactly one `.listen()` for the
/// whole lifetime of the connection (the same lesson ADR 0030 already
/// hit for `RemoteControlServer`/`Client`), and this is always
/// constructed *from inside* the one persistent `listen()` callback the
/// owning server/client code already has going for the hello handshake
/// (`playback_ownership_server.dart`/`playback_ownership_client.dart`).
/// Callers feed it messages via [handleIncoming]/[handleClosed] instead.
///
/// Owns its own liveness: sends a heartbeat every 4s and calls [onLost]
/// if nothing at all (heartbeat or otherwise) has been received for
/// 20s — deliberately more forgiving than `PeerPresenceTracker`'s 6s
/// mDNS `PeerLost` debounce (docs/adr/0025-sync-and-discovery-reliability.md):
/// mDNS presence is "is the peer still broadcasting", cheap to declare
/// lost and re-detect moments later from the next re-announce; this is
/// "is our live ownership socket still good", and declaring it lost
/// pauses local playback (see `PlaybackOwnershipCoordinator._handleIncomingSelfClaim`/
/// `_handleGossip`) — a false positive from an ordinary OS scheduling
/// hiccup (a phone's network stack briefly deprioritized while the
/// screen is off, a momentary Wi-Fi blip) is far more disruptive here
/// than being a few extra seconds slow to notice a *genuine* drop.
class PlaybackOwnershipLink {
  PlaybackOwnershipLink({
    required this.remoteDeviceId,
    required WebSocket socket,
    Duration heartbeatInterval = const Duration(seconds: 4),
    Duration lostTimeout = const Duration(seconds: 20),
  })  : _socket = socket,
        _lostTimeout = lostTimeout {
    _lastReceivedAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => send(const OwnershipHeartbeat()));
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(_lastReceivedAt) >= _lostTimeout) _handleLost();
    });
  }

  final String remoteDeviceId;
  final WebSocket _socket;
  final Duration _lostTimeout;

  /// Settable, not constructor-only — this link is constructed by the
  /// owning server/client code before the
  /// `PlaybackOwnershipCoordinator` that actually cares about loss ever
  /// sees it (see this class's doc); the coordinator assigns this
  /// immediately upon receiving the link, well before any real timeout
  /// or close could occur. Defaults to a no-op so an unassigned link
  /// never crashes on loss.
  void Function() onLost = _noop;
  static void _noop() {}

  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  late DateTime _lastReceivedAt;
  bool _lost = false;

  final _messagesController = StreamController<OwnershipMessage>.broadcast();
  Stream<OwnershipMessage> get messages => _messagesController.stream;

  void send(OwnershipMessage message) {
    try {
      _socket.add(jsonEncode(message.toJson()));
    } catch (_) {
      // Socket already closing — irrelevant, the watchdog/onDone handler
      // will call [onLost] shortly regardless.
    }
  }

  /// Called by the owning server/client's single persistent
  /// `socket.listen()` for every message once past the hello handshake.
  void handleIncoming(Object? raw) {
    _lastReceivedAt = DateTime.now();
    if (raw is! String) return;
    final Map<String, Object?> json;
    try {
      json = jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return;
    }
    final message = OwnershipMessage.fromJson(json);
    if (message != null) _messagesController.add(message);
  }

  /// Called by the owning listen's `onDone`/`onError`.
  void handleClosed() => _handleLost();

  void _handleLost() {
    if (_lost) return;
    _lost = true;
    onLost();
    dispose();
  }

  /// Also reachable directly (not just via [_handleLost]) — a
  /// coordinator tearing itself down disposes every link explicitly.
  /// Setting [_lost] here too, not just in [_handleLost], matters: the
  /// underlying `socket.close()` below is async and fire-and-forget, so
  /// its `onDone` can still reach [handleClosed] afterward — without
  /// this guard, that would call [onLost] a second time, on a
  /// coordinator that may already consider itself fully torn down (its
  /// own stream controllers already closed).
  void dispose() {
    _lost = true;
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    unawaited(_messagesController.close());
    try {
      unawaited(_socket.close());
    } catch (_) {
      // Already closed.
    }
  }
}
