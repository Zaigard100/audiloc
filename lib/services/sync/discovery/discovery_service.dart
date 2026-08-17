import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovered_peer.dart';
import 'discovery_event.dart';
import 'peer_presence_tracker.dart';

/// Finds other AudiLoc installations on the LAN via mDNS/Bonjour (ТЗ п.3,
/// "Обнаружение устройств в LAN" → bonsoir) and advertises this one.
///
/// This only does discovery — it doesn't open any sync connection itself.
/// `MetadataSyncService` listens to [events] and decides what to do with a
/// found/lost peer. Raw bonsoir found/lost signals are debounced and
/// replayed to late subscribers by [PeerPresenceTracker] — see its doc and
/// docs/adr/0025-sync-and-discovery-reliability.md for why every consumer
/// (`SyncOrchestrator`, `FileSyncService`/`CoverSyncService`, the
/// Устройства-screen providers) needed that rather than reacting to raw
/// bonsoir events directly.
class DiscoveryService {
  DiscoveryService({
    required String selfDeviceId,
    required String selfDeviceName,
    Duration lostDebounce = const Duration(seconds: 6),
  })  : _selfDeviceId = selfDeviceId,
        _selfDeviceName = selfDeviceName,
        _presence = PeerPresenceTracker(lostDebounce: lostDebounce);

  static const _serviceType = '_audiloc._tcp';

  final String _selfDeviceId;
  final String _selfDeviceName;
  final PeerPresenceTracker _presence;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  Stream<DiscoveryEvent> get events => _presence.events;

  /// Publishes this device on the LAN so peers can find it. [port] is the
  /// local `MetadataSyncService` WebSocket port.
  Future<void> startAdvertising(int port) async {
    final service = BonsoirService(
      name: _selfDeviceName,
      type: _serviceType,
      port: port,
      attributes: {'id': _selfDeviceId},
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> stopAdvertising() async {
    await _broadcast?.stop();
    _broadcast = null;
  }

  Future<void> startDiscovery() async {
    final discovery = BonsoirDiscovery(type: _serviceType);
    await discovery.initialize();
    // Subscribe before start() so no early event is missed.
    _discovery = discovery;
    _discoverySub = discovery.eventStream!.listen(_handleEvent);
    await discovery.start();
  }

  Future<void> stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery?.stop();
    _discovery = null;
  }

  /// Tears down and re-establishes both advertising and discovery from
  /// scratch. [SyncOrchestrator.restartDiscovery] is the only caller —
  /// see its doc and docs/adr/0026-manual-discovery-refresh.md for why
  /// this exists alongside the automatic debounce/replay in
  /// [PeerPresenceTracker]: an OS-level mDNS listener stuck after a Wi-Fi
  /// switch or doze/sleep never produces the found/lost events that
  /// automatic recovery relies on in the first place, so nothing short of
  /// an actual restart fixes it.
  Future<void> restart(int port) async {
    _presence.reset();
    await stopAdvertising();
    await stopDiscovery();
    await startAdvertising(port);
    await startDiscovery();
  }

  /// Same underlying fix as [restart] — tears down and re-establishes
  /// the native mDNS listener/broadcast, the only thing that actually
  /// recovers a stuck one (see [restart]'s doc) — but *without*
  /// [PeerPresenceTracker.reset]'s immediate "every known peer just
  /// went offline" signal. [restart] is for the deliberate, user-visible
  /// "обновить" button, where that flicker is an expected, momentary
  /// side effect of an explicit action; this is for
  /// [SyncOrchestrator]'s own periodic self-healing timer, where nobody
  /// asked for anything and peers that are still genuinely online must
  /// not visibly flap offline-then-online-again once a minute. Any peer
  /// still actually there gets an ordinary [PeerPresenceTracker.markFound]
  /// once re-discovered, which is a no-op for the UI (already known
  /// online); one that's genuinely gone still gets caught by the normal
  /// debounced [PeerPresenceTracker.scheduleLost] path, same as any
  /// other loss.
  Future<void> refresh(int port) async {
    await stopAdvertising();
    await stopDiscovery();
    await startAdvertising(port);
    await startDiscovery();
  }

  void _handleEvent(BonsoirDiscoveryEvent event) {
    final discovery = _discovery;
    if (discovery == null) return;
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        event.service.resolve(discovery.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        final peer = _peerFrom(event.service);
        if (peer != null) _presence.markFound(peer);
      case BonsoirDiscoveryServiceLostEvent():
        final id = event.service.attributes['id'];
        if (id != null && id != _selfDeviceId) _presence.scheduleLost(id);
      default:
        break;
    }
  }

  DiscoveredPeer? _peerFrom(BonsoirService service) {
    final id = service.attributes['id'];
    if (id == null || id == _selfDeviceId) return null;
    if (service.hostAddresses.isEmpty) return null;
    return DiscoveredPeer(
      deviceId: id,
      name: service.name,
      host: service.hostAddresses.first,
      port: service.port,
    );
  }

  Future<void> dispose() async {
    await stopAdvertising();
    await stopDiscovery();
    await _presence.dispose();
  }
}
