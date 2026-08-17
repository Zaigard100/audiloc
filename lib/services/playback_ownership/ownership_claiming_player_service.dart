import '../../data/models/track.dart';
import '../playback/player_service.dart';
import 'playback_ownership_coordinator.dart';
import 'playback_ownership_models.dart';

/// Wraps this device's local [PlayerService], firing a reactive ownership
/// claim as a side effect of any call that starts local audio —
/// `play()`, a resuming `playOrPause()`, or `setQueue(autoPlay: true)`.
/// Every other method delegates 1:1, unchanged. See
/// docs/adr/0033-playback-ownership-and-handoff.md.
///
/// The claim is fire-and-forget (`PlaybackOwnershipCoordinator.claimSelf`
/// doesn't block on anything) and a no-op while the profile-wide sync
/// toggle is off — this decorator is applied to `playerServiceProvider`
/// unconditionally, so every other reader of that provider (the mini
/// player, keyboard shortcuts, `PlaybackStateWriter`, incoming remote
/// control from another device) keeps working exactly as before,
/// regardless of whether sync is on.
class OwnershipClaimingPlayerService implements PlayerService {
  OwnershipClaimingPlayerService(this._inner, this._coordinator);

  final PlayerService _inner;
  final PlaybackOwnershipCoordinator _coordinator;

  @override
  Stream<bool> get playingStream => _inner.playingStream;
  @override
  Stream<PlaybackPositionState> get positionStream => _inner.positionStream;
  @override
  Stream<Track?> get currentTrackStream => _inner.currentTrackStream;
  @override
  Stream<bool> get completedStream => _inner.completedStream;
  @override
  Stream<bool> get shuffleStream => _inner.shuffleStream;
  @override
  Stream<PlaybackRepeatMode> get repeatModeStream => _inner.repeatModeStream;

  @override
  bool get isPlaying => _inner.isPlaying;
  @override
  Track? get currentTrack => _inner.currentTrack;
  @override
  bool get isShuffleEnabled => _inner.isShuffleEnabled;
  @override
  PlaybackRepeatMode get repeatMode => _inner.repeatMode;
  @override
  Duration get position => _inner.position;
  @override
  List<Track> get queue => _inner.queue;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
    Duration? seekTo,
  }) {
    if (autoPlay) _coordinator.claimSelf(reason: ClaimReason.localPlay);
    return _inner.setQueue(
      tracks,
      startIndex: startIndex,
      autoPlay: autoPlay,
      seekTo: seekTo,
    );
  }

  @override
  Future<void> play() {
    _coordinator.claimSelf(reason: ClaimReason.localPlay);
    return _inner.play();
  }

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> playOrPause() {
    if (!_inner.isPlaying)
      _coordinator.claimSelf(reason: ClaimReason.localPlay);
    return _inner.playOrPause();
  }

  @override
  Future<void> seek(Duration position) => _inner.seek(position);

  @override
  Future<void> next() => _inner.next();

  @override
  Future<void> previous() => _inner.previous();

  @override
  Future<void> setShuffle(bool enabled) => _inner.setShuffle(enabled);

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      _inner.setRepeatMode(mode);

  @override
  Future<void> dispose() => _inner.dispose();
}
