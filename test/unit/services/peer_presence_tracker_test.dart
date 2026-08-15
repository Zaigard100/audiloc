import 'package:audiloc/services/sync/discovery/discovered_peer.dart';
import 'package:audiloc/services/sync/discovery/discovery_event.dart';
import 'package:audiloc/services/sync/discovery/peer_presence_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// See docs/adr/0025-sync-and-discovery-reliability.md — this logic used
/// to live directly in `DiscoveryService`, which wraps a real bonsoir
/// platform channel and can't be exercised in a plain unit test. Pulled
/// out specifically so the debounce/replay behavior itself is testable.
void main() {
  const peer = DiscoveredPeer(deviceId: 'peer-1', name: 'Peer Phone', host: '192.168.1.10', port: 8541);

  group('PeerPresenceTracker', () {
    test('a lost signal quickly followed by a found signal never surfaces the loss', () async {
      final tracker = PeerPresenceTracker(lostDebounce: const Duration(milliseconds: 50));
      addTearDown(tracker.dispose);

      final events = <DiscoveryEvent>[];
      final sub = tracker.events.listen(events.add);

      tracker.markFound(peer);
      tracker.scheduleLost(peer.deviceId);
      tracker.markFound(peer); // arrives well within lostDebounce

      await Future.delayed(const Duration(milliseconds: 120));
      await sub.cancel();

      expect(events.whereType<PeerLost>(), isEmpty);
      expect(events.whereType<PeerFound>().length, 2);
    });

    test('a loss that is never cancelled surfaces after the debounce window', () async {
      final tracker = PeerPresenceTracker(lostDebounce: const Duration(milliseconds: 30));
      addTearDown(tracker.dispose);

      final events = <DiscoveryEvent>[];
      final sub = tracker.events.listen(events.add);

      tracker.markFound(peer);
      tracker.scheduleLost(peer.deviceId);

      await Future.delayed(const Duration(milliseconds: 80));
      await sub.cancel();

      expect(events.whereType<PeerLost>().map((e) => e.deviceId), [peer.deviceId]);
    });

    test('a new subscriber immediately sees already-known peers, not just future events', () async {
      final tracker = PeerPresenceTracker();
      addTearDown(tracker.dispose);

      tracker.markFound(peer);
      // A late subscriber — the whole point being fixed here — must not
      // have to wait for another live event to learn this peer exists.
      final first = await tracker.events.first.timeout(const Duration(seconds: 2));

      expect(first, isA<PeerFound>());
      expect((first as PeerFound).peer.deviceId, peer.deviceId);
    });

    test('a peer removed by a completed loss is not replayed to later subscribers', () async {
      final tracker = PeerPresenceTracker(lostDebounce: const Duration(milliseconds: 20));
      addTearDown(tracker.dispose);

      tracker.markFound(peer);
      tracker.scheduleLost(peer.deviceId);
      await Future.delayed(const Duration(milliseconds: 60));

      final events = <DiscoveryEvent>[];
      final sub = tracker.events.listen(events.add);
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(events, isEmpty);
    });
  });
}
