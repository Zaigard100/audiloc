import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovered_peer.dart';
import 'discovery_event.dart';

/// Finds other AudiLoc installations on the LAN via mDNS/Bonjour (ТЗ п.3,
/// "Обнаружение устройств в LAN" → bonsoir) and advertises this one.
///
/// This only does discovery — it doesn't open any sync connection itself.
/// `MetadataSyncService` listens to [events] and decides what to do with a
/// found/lost peer.
class DiscoveryService {
  DiscoveryService({
    required String selfDeviceId,
    required String selfDeviceName,
  })  : _selfDeviceId = selfDeviceId,
        _selfDeviceName = selfDeviceName;

  static const _serviceType = '_audiloc._tcp';

  final String _selfDeviceId;
  final String _selfDeviceName;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  final _eventsController = StreamController<DiscoveryEvent>.broadcast();

  Stream<DiscoveryEvent> get events => _eventsController.stream;

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

  void _handleEvent(BonsoirDiscoveryEvent event) {
    final discovery = _discovery;
    if (discovery == null) return;
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        event.service.resolve(discovery.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        final peer = _peerFrom(event.service);
        if (peer != null) _eventsController.add(PeerFound(peer));
      case BonsoirDiscoveryServiceLostEvent():
        final id = event.service.attributes['id'];
        if (id != null && id != _selfDeviceId) {
          _eventsController.add(PeerLost(id));
        }
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
    await _eventsController.close();
  }
}
