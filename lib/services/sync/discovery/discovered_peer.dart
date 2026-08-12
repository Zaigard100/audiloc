/// A peer found on the LAN via mDNS, resolved enough to connect to.
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.name,
    required this.host,
    required this.port,
  });

  /// The peer's CRDT node id, carried in the mDNS TXT record — this is
  /// what lets us match a discovery event back to a `devices` row.
  final String deviceId;
  final String name;
  final String host;
  final int port;

  Uri get metadataSyncUri => Uri(scheme: 'ws', host: host, port: port);
}
