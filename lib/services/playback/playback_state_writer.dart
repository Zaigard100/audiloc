import 'dart:async';

import '../../data/local_playback_state_store.dart';
import '../../data/models/device.dart';
import '../../data/models/playback_state.dart';
import '../../data/repositories/playback_state_repository.dart';
import '../../features/player/models/queue_source.dart';
import 'player_service.dart';

/// Persists "what's playing, and where" to two independent places — see
/// docs/adr/0029-playback-state-sync.md. [_handlePlayingChanged] does
/// this automatically *only* on a playing→paused edge, not on every
/// position tick, which would turn a CRDT-synced table into a write
/// storm sent to every paired peer several times a second — same lesson
/// already learned the hard way about `devices.last_online_at`
/// (docs/adr/0025-sync-and-discovery-reliability.md). [saveCurrentState]
/// is the other, explicit trigger: [AudilocApp] calls it directly on
/// app-lifecycle events (backgrounded, window closing) so leaving
/// mid-playback — not just an explicit pause — still leaves a bookmark.
class PlaybackStateWriter {
  PlaybackStateWriter({
    required PlayerService playerService,
    required PlaybackStateRepository repository,
    required LocalPlaybackStateStore localStore,
    required Device selfDevice,
    required QueueSource? Function() currentQueueSource,
    required bool Function() isSendEnabled,
    required bool Function() isLocalSaveEnabled,
  })  : _playerService = playerService,
        _repository = repository,
        _localStore = localStore,
        _selfDevice = selfDevice,
        _currentQueueSource = currentQueueSource,
        _isSendEnabled = isSendEnabled,
        _isLocalSaveEnabled = isLocalSaveEnabled;

  final PlayerService _playerService;
  final PlaybackStateRepository _repository;
  final LocalPlaybackStateStore _localStore;
  final Device _selfDevice;
  final QueueSource? Function() _currentQueueSource;

  /// The Settings "отправлять" toggle (cross-device CRDT sync) — read
  /// fresh on every call (not captured once at construction), same
  /// pattern as `RemoteControlServer`'s `isAllowed`.
  final bool Function() _isSendEnabled;

  /// The Settings "сохранять состояние прошлой сессии" toggle — purely
  /// local, independent of [_isSendEnabled]. On by default (see
  /// `core/providers.dart`'s `currentSaveLocalSessionProvider`), unlike
  /// the cross-device toggles: this never leaves the device.
  final bool Function() _isLocalSaveEnabled;

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
    unawaited(saveCurrentState());
  }

  /// Writes whatever's currently loaded, regardless of playing/paused —
  /// unlike [_handlePlayingChanged], which only fires on an explicit
  /// pause. Used by [AudilocApp] on app-lifecycle events (backgrounded /
  /// window closing) so a bookmark still lands even if the user leaves
  /// mid-playback rather than pausing first. A no-op if nothing's loaded,
  /// or if both [_isLocalSaveEnabled] and [_isSendEnabled] are off.
  Future<void> saveCurrentState() async {
    final localEnabled = _isLocalSaveEnabled();
    final sendEnabled = _isSendEnabled();
    if (!localEnabled && !sendEnabled) return;

    final track = _playerService.currentTrack;
    if (track == null) return;

    final source = _currentQueueSource();
    final (queueType, playlistId) = switch (source) {
      PlaylistQueueSource(:final playlistId) => (PlaybackQueueType.playlist, playlistId),
      FavoritesQueueSource() => (PlaybackQueueType.favorites, null),
      LibraryQueueSource() || null => (PlaybackQueueType.library, null),
    };

    final state = PlaybackState(
      trackId: track.id,
      positionMs: _playerService.position.inMilliseconds,
      queueType: queueType,
      playlistId: playlistId,
      deviceId: _selfDevice.id,
      deviceName: _selfDevice.name,
    );

    await Future.wait([
      if (localEnabled) _localStore.write(state),
      if (sendEnabled) _repository.save(state),
    ]);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
