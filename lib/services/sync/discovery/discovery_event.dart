import 'discovered_peer.dart';

sealed class DiscoveryEvent {
  const DiscoveryEvent();
}

class PeerFound extends DiscoveryEvent {
  const PeerFound(this.peer);

  final DiscoveredPeer peer;
}

class PeerLost extends DiscoveryEvent {
  const PeerLost(this.deviceId);

  final String deviceId;
}
