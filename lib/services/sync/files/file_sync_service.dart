import 'dart:async';
import 'dart:io';

import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../discovery/discovery_event.dart';
import '../discovery/discovery_service.dart';
import 'file_transfer_client.dart';

/// The "клей" (glue) that turns "I know about a track but don't have the
/// file" into an actual download: watches
/// `TracksRepository.watchMissingFiles()`, and for each one, asks
/// `track_locations` (already synced — see docs/adr/0009) which peers
/// have a copy, picks one that's currently online (per
/// `DiscoveryService`), and fetches it via [FileTransferClient].
///
/// Deliberately reuses the exact same LAN connectivity and discovery this
/// app already has for metadata sync, rather than a second protocol/app
/// — see docs/adr/0010-built-in-file-transfer.md for why this replaced
/// the earlier Syncthing-based design.
class FileSyncService {
  FileSyncService({
    required TracksRepository tracksRepository,
    required DiscoveryService discoveryService,
    required FileTransferClient client,
    required Directory downloadsDir,
    this.filePort = 8542,
  })  : _tracksRepository = tracksRepository,
        _discoveryService = discoveryService,
        _client = client,
        _downloadsDir = downloadsDir {
    _discoverySub = _discoveryService.events.listen(_handleDiscoveryEvent);
  }

  final TracksRepository _tracksRepository;
  final DiscoveryService _discoveryService;
  final FileTransferClient _client;
  final Directory _downloadsDir;
  final int filePort;

  final _onlineHosts = <String, String>{}; // deviceId -> LAN host
  final _inFlight = <String>{}; // trackIds currently downloading
  List<Track> _lastMissing = const [];

  StreamSubscription<DiscoveryEvent>? _discoverySub;
  StreamSubscription<List<Track>>? _missingSub;

  void start() {
    _missingSub = _tracksRepository.watchMissingFiles().listen((missing) {
      _lastMissing = missing;
      unawaited(_tryDownloadMissing(missing));
    });
  }

  void _handleDiscoveryEvent(DiscoveryEvent event) {
    switch (event) {
      case PeerFound(:final peer):
        _onlineHosts[peer.deviceId] = peer.host;
        // A peer just appeared — it might be the one holding a file we've
        // been waiting for, so give the current missing list another pass
        // instead of waiting for the track list to change again.
        unawaited(_tryDownloadMissing(_lastMissing));
      case PeerLost(:final deviceId):
        _onlineHosts.remove(deviceId);
    }
  }

  Future<void> _tryDownloadMissing(List<Track> missing) async {
    for (final track in missing) {
      if (_inFlight.contains(track.id)) continue;

      final peers = await _tracksRepository.peersWithLocalCopy(track.id);
      String? host;
      for (final peerId in peers) {
        final peerHost = _onlineHosts[peerId];
        if (peerHost != null) {
          host = peerHost;
          break;
        }
      }
      if (host == null) continue;

      _inFlight.add(track.id);
      unawaited(_downloadOne(track.id, host).whenComplete(() => _inFlight.remove(track.id)));
    }
  }

  Future<void> _downloadOne(String trackId, String host) async {
    try {
      if (!await _downloadsDir.exists()) {
        await _downloadsDir.create(recursive: true);
      }
      final path = await _client.download(
        host: host,
        port: filePort,
        trackId: trackId,
        destinationDir: _downloadsDir,
      );
      await _tracksRepository.recordLocalFile(trackId, path);
    } catch (_) {
      // Peer went offline mid-transfer, network hiccup, etc. — the next
      // watchMissingFiles emission or peer-found event will retry.
    }
  }

  Future<void> dispose() async {
    await _discoverySub?.cancel();
    await _missingSub?.cancel();
  }
}
