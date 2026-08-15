import 'dart:async';

import '../../data/models/device.dart';
import '../../data/models/playback_state.dart';
import '../../data/repositories/playback_state_repository.dart';
import '../../features/player/models/queue_source.dart';
import 'player_service.dart';

/// Persists "what's playing, and where" every time playback pauses —
/// deliberately *only* on a playing→paused edge, not on every position
/// tick, which would turn a CRDT-synced table into a write storm sent to
/// every paired peer several times a second. Same lesson already learned
/// the hard way about `devices.last_online_at` —
/// docs/adr/0025-sync-and-discovery-reliability.md — applied here from
/// the start; see docs/adr/0029-playback-state-sync.md.
class PlaybackStateWriter {
  PlaybackStateWriter({
    required PlayerService playerService,
    required PlaybackStateRepository repository,
    required Device selfDevice,
    required QueueSource? Function() currentQueueSource,
  })  : _playerService = playerService,
        _repository = repository,
        _selfDevice = selfDevice,
        _currentQueueSource = currentQueueSource;

  final PlayerService _playerService;
  final PlaybackStateRepository _repository;
  final Device _selfDevice;
  final QueueSource? Function() _currentQueueSource;

  StreamSubscription<bool>? _sub;
  bool? _wasPlaying;

  void start() {
    _sub = _playerService.playingStream.listen(_handlePlayingChanged);
  }

  void _handlePlayingChanged(bool playing) {
    final wasPlaying = _wasPlaying;
    _wasPlaying = playing;
    // Only the true -> false edge is a "pause" — both "already were
    // paused" (nothing changed) and "just started/resumed playing" must
    // not write.
    if (wasPlaying != true || playing) return;

    final track = _playerService.currentTrack;
    if (track == null) return; // playback stopped outright, nothing to bookmark

    final source = _currentQueueSource();
    final (queueType, playlistId) = switch (source) {
      PlaylistQueueSource(:final playlistId) => (PlaybackQueueType.playlist, playlistId),
      FavoritesQueueSource() => (PlaybackQueueType.favorites, null),
      LibraryQueueSource() || null => (PlaybackQueueType.library, null),
    };

    unawaited(_repository.save(PlaybackState(
      trackId: track.id,
      positionMs: _playerService.position.inMilliseconds,
      queueType: queueType,
      playlistId: playlistId,
      deviceId: _selfDevice.id,
      deviceName: _selfDevice.name,
    )));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
