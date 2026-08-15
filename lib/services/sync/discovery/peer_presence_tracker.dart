import 'dart:async';

import 'discovered_peer.dart';
import 'discovery_event.dart';

/// Turns raw, possibly-flappy found/lost signals (mDNS re-announce cycles,
/// one dropped multicast packet — see `DiscoveryService`, the only caller)
/// into stable [DiscoveryEvent]s, and replays the current snapshot to every
/// new subscriber of [events].
///
/// Pulled out of `DiscoveryService` itself so this logic is testable
/// without a real bonsoir platform channel — see
/// docs/adr/0025-sync-and-discovery-reliability.md.
class PeerPresenceTracker {
  PeerPresenceTracker({this.lostDebounce = const Duration(seconds: 6)});

  final Duration lostDebounce;

  final _known = <String, DiscoveredPeer>{};
  final _lostTimers = <String, Timer>{};
  final _eventsController = StreamController<DiscoveryEvent>.broadcast();

  /// Replays the currently-known peers as synthetic [PeerFound] events to
  /// every new listener before forwarding live events — a plain broadcast
  /// stream only delivers events that happen *after* `.listen`, which left
  /// a peer resolved before some late subscriber (e.g. a UI provider first
  /// watched well after startup) looking permanently offline until
  /// unrelated network activity happened to produce another live event
  /// for it.
  Stream<DiscoveryEvent> get events => Stream.multi((controller) {
        for (final peer in _known.values) {
          controller.add(PeerFound(peer));
        }
        final sub = _eventsController.stream.listen(controller.add, onDone: controller.close);
        controller.onCancel = sub.cancel;
      }, isBroadcast: true);

  /// A found/resolved signal always means the peer is here *now* —
  /// cancels any pending debounced loss for it, even if this particular
  /// signal is just a routine re-announce rather than a genuine recovery
  /// from a drop.
  void markFound(DiscoveredPeer peer) {
    _lostTimers.remove(peer.deviceId)?.cancel();
    _known[peer.deviceId] = peer;
    _eventsController.add(PeerFound(peer));
  }

  /// Doesn't emit [PeerLost] immediately — holds it for [lostDebounce] so
  /// a near-simultaneous [markFound] for the same id (a normal mDNS TTL
  /// re-announce cycle, not a real drop) cancels it before anyone
  /// downstream ever sees the loss.
  void scheduleLost(String id) {
    _lostTimers[id]?.cancel();
    _lostTimers[id] = Timer(lostDebounce, () {
      _lostTimers.remove(id);
      _known.remove(id);
      _eventsController.add(PeerLost(id));
    });
  }

  Future<void> dispose() async {
    for (final timer in _lostTimers.values) {
      timer.cancel();
    }
    _lostTimers.clear();
    _known.clear();
    await _eventsController.close();
  }
}
