import 'dart:async';
import 'dart:io';

import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../discovery/discovery_event.dart';
import '../discovery/discovery_service.dart';
import 'file_transfer_client.dart';

/// The cover-art counterpart to [FileSyncService]: watches
/// `TracksRepository.watchMissingCovers()` and fetches each one from
/// whichever online peer has it, over the same LAN connectivity and the
/// same server (`FileTransferServer`'s `/covers/<id>` route) — see
/// docs/adr/0012-local-cover-paths.md.
class CoverSyncService {
  CoverSyncService({
    required TracksRepository tracksRepository,
    required DiscoveryService discoveryService,
    required FileTransferClient client,
    required Directory coverCacheDir,
    this.filePort = 8542,
  })  : _tracksRepository = tracksRepository,
        _discoveryService = discoveryService,
        _client = client,
        _coverCacheDir = coverCacheDir {
    _discoverySub = _discoveryService.events.listen(_handleDiscoveryEvent);
  }

  final TracksRepository _tracksRepository;
  final DiscoveryService _discoveryService;
  final FileTransferClient _client;
  final Directory _coverCacheDir;
  final int filePort;

  final _onlineHosts = <String, String>{}; // deviceId -> LAN host
  final _inFlight = <String>{}; // trackIds currently downloading a cover
  List<Track> _lastMissing = const [];

  StreamSubscription<DiscoveryEvent>? _discoverySub;
  StreamSubscription<List<Track>>? _missingSub;

  void start() {
    _missingSub = _tracksRepository.watchMissingCovers().listen((missing) {
      _lastMissing = missing;
      unawaited(_tryDownloadMissing(missing));
    });
  }

  void _handleDiscoveryEvent(DiscoveryEvent event) {
    switch (event) {
      case PeerFound(:final peer):
        _onlineHosts[peer.deviceId] = peer.host;
        // A peer just appeared — it might have a cover we've been
        // waiting for, so give the current missing list another pass.
        unawaited(_tryDownloadMissing(_lastMissing));
      case PeerLost(:final deviceId):
        _onlineHosts.remove(deviceId);
    }
  }

  Future<void> _tryDownloadMissing(List<Track> missing) async {
    for (final track in missing) {
      if (_inFlight.contains(track.id)) continue;

      final peers = await _tracksRepository.peersWithLocalCover(track.id);
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
      if (!await _coverCacheDir.exists()) {
        await _coverCacheDir.create(recursive: true);
      }
      final path = await _client.downloadCover(
        host: host,
        port: filePort,
        trackId: trackId,
        destinationDir: _coverCacheDir,
      );
      await _tracksRepository.recordLocalCover(trackId, path);
    } catch (_) {
      // Peer went offline mid-transfer, network hiccup, etc. — the next
      // watchMissingCovers emission or peer-found event will retry.
    }
  }

  Future<void> dispose() async {
    await _discoverySub?.cancel();
    await _missingSub?.cancel();
  }
}
