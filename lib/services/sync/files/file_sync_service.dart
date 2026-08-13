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

  final _events = StreamController<TransferEvent>.broadcast();

  /// Progress for downloads currently in flight — UI subscribes to this
  /// to show something better than a static "waiting" count.
  Stream<TransferEvent> get transferEvents => _events.stream;

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
        onProgress: (received, total) =>
            _events.add(TransferProgress(trackId, receivedBytes: received, totalBytes: total)),
      );
      await _tracksRepository.recordLocalFile(trackId, path);
    } catch (_) {
      // Peer went offline mid-transfer, network hiccup, etc. — the next
      // watchMissingFiles emission or peer-found event will retry.
    } finally {
      _events.add(TransferFinished(trackId));
    }
  }

  Future<void> dispose() async {
    await _discoverySub?.cancel();
    await _missingSub?.cancel();
    await _events.close();
  }
}

/// Emitted on [FileSyncService.transferEvents] while a track is being
/// downloaded from a peer.
sealed class TransferEvent {
  const TransferEvent(this.trackId);
  final String trackId;
}

/// A chunk of a download landed. [fraction] is `null` when the server
/// didn't report a length (`totalBytes < 0`) — callers should show an
/// indeterminate indicator rather than guess.
class TransferProgress extends TransferEvent {
  const TransferProgress(super.trackId, {required this.receivedBytes, required this.totalBytes});
  final int receivedBytes;
  final int totalBytes;

  double? get fraction => totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0, 1) : null;
}

/// The download for [trackId] stopped, successfully or not — either way,
/// it's no longer "in flight" and UI should drop it from any active list.
/// (Whether it actually succeeded is visible separately, through
/// `TracksRepository.watchMissingFiles()`.)
class TransferFinished extends TransferEvent {
  const TransferFinished(super.trackId);
}
